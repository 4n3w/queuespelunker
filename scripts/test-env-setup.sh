#!/usr/bin/env bash

set -euo pipefail

source colours.sh

echo_step() {
  echo -e "${BLUE}==> $1${NC}"
}

echo_success() {
  echo -e "${GREEN}==> $1${NC}"
}

echo_wait() {
  echo -e "${YELLOW}==> $1${NC}"
}

wait_for_service() {
    local service_name=$1
    local max_attempts=60  # 15 minutes with 15 second delay
    local attempt=1

    echo_wait "Waiting for service instance $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        status=$(cf service "$service_name" | grep "status:" || true)
        
        if [[ $status == *"create succeeded"* ]]; then
            echo_success "Service instance $service_name is ready!"
            return 0
        elif [[ $status == *"failed"* ]]; then
            echo "Service instance $service_name failed to create"
            return 1
        fi

        echo_wait "Attempt $attempt/$max_attempts: Service instance still creating..."
        sleep 15
        ((attempt++))
    done

    echo "Timeout waiting for service instance $service_name"
    return 1
}

create_service_and_wait() {
    local service_name=$1
    
    echo_step "Creating service instance: $service_name"
    cf create-service p.rabbitmq on-demand-plan "$service_name" || true
    
    wait_for_service "$service_name"
    
    echo_step "Creating service key for: $service_name"
    cf create-service-key "$service_name" admin-key || true
    
    # Wait a few seconds for the service key to be fully ready
    sleep 5
}

ORGS=("test-org-alpha" "test-org-beta" "test-org-gamma")
SPACES=("dev" "qa")

for org in "${ORGS[@]}"; do
  echo_step "Creating organization: $org"
  cf create-org "$org" || true
    
  for space in "${SPACES[@]}"; do
    echo_step "Creating space: $space in org: $org"
    cf target -o "$org"
    cf create-space "$space" || true
  done
done

echo_step "Creating RabbitMQ service instances..."

# Alpha Org - Deprecated Mirrored Queues
cf target -o "test-org-alpha" -s "dev"
create_service_and_wait "rabbitmq-alpha-dev"


CREDS=$(cf service-key rabbitmq-alpha-dev admin-key | awk 'NR>2')
API_URL=$(echo "$CREDS" | jq -r '.dashboard_url | sub("/#/"; "/api/")')
USERNAME=$(echo "$CREDS" | jq -r '.username')
PASSWORD=$(echo "$CREDS" | jq -r '.password')

echo_step "Setting up mirrored queue policy in test-org-alpha"
curl -u "$USERNAME:$PASSWORD" "$API_URL/policies/%2f/ha-policy" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d '{
        "pattern": "^mirror.*",
        "definition": {
            "ha-mode": "exactly",
            "ha-params": 2,
            "ha-sync-mode": "automatic"
        }
    }'

# Org Beta - With deprecated mirrored queues but different pattern
cf target -o "test-org-beta" -s "qa"
create_service_and_wait "rabbitmq-beta-qa"

CREDS=$(cf service-key rabbitmq-beta-qa admin-key | awk 'NR>2')
API_URL=$(echo "$CREDS" | jq -r '.dashboard_url | sub("/#/"; "/api/")')
USERNAME=$(echo "$CREDS" | jq -r '.username')
PASSWORD=$(echo "$CREDS" | jq -r '.password')

echo_step "Setting up mirrored queue policy in test-org-beta"

curl -u "$USERNAME:$PASSWORD" "$API_URL/policies/%2f/ha-policy-beta" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d '{
        "pattern": "^beta.*",
        "definition": {
            "ha-mode": "all",
            "ha-sync-mode": "automatic"
        }
    }'

# Org Gamma - With modern queue types only
cf target -o "test-org-gamma" -s "dev"
create_service_and_wait "rabbitmq-gamma-dev"

CREDS=$(cf service-key rabbitmq-gamma-dev admin-key | awk 'NR>2')
API_URL=$(echo "$CREDS" | jq -r '.dashboard_url | sub("/#/"; "/api/")')
USERNAME=$(echo "$CREDS" | jq -r '.username')
PASSWORD=$(echo "$CREDS" | jq -r '.password')

echo_step "Setting up modern queue policy in test-org-gamma"
curl -u "$USERNAME:$PASSWORD" "$API_URL/policies/%2f/modern-policy" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d '{
        "pattern": "^q.*",
        "definition": {
            "queue-mode": "lazy",
            "queue-type": "quorum"
        }
    }'

echo_success "Setup complete! Created:"
echo "- 3 organizations with 2 spaces each"
echo "- RabbitMQ instances with:"
echo "  * Mirrored queues in test-org-alpha (pattern: ^mirror.*)"
echo "  * Mirrored queues in test-org-beta (pattern: ^beta.*)"
echo "  * Modern quorum queues in test-org-gamma (pattern: ^q.*)"


