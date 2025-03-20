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

create_service_without_key() {
    local service_name=$1

    echo_step "Creating service instance without key: $service_name"
    cf create-service p.rabbitmq on-demand-plan "$service_name" || true

    wait_for_service "$service_name"
}


create_dummy_app() {
    local app_name=$1
    local temp_dir=$(mktemp -d)

    # Print status to stderr so it doesn't get captured in command substitution
    echo_step "Creating dummy app files for: $app_name in $temp_dir" >&2

    # Create a minimal static website
    echo "<html><body><h1>Dummy App for RabbitMQ Testing</h1></body></html>" > "$temp_dir/index.html"

    # Create a manifest.yml
    cat > "$temp_dir/manifest.yml" <<EOL
---
applications:
- name: $app_name
  memory: 64M
  instances: 1
  buildpacks:
  - staticfile_buildpack
  env:
    FORCE_HTTPS: false
EOL

    # Create Staticfile for the buildpack
    echo "root: ." > "$temp_dir/Staticfile"

    # Just return the directory path without any additional output
    echo "$temp_dir"
}

push_and_bind_app() {
    local app_dir=$1
    local app_name=$2
    local service_name=$3

    echo_step "Pushing app: $app_name"
    pushd "$app_dir" > /dev/null
    cf push "$app_name" --no-start
    popd > /dev/null

    echo_step "Binding service: $service_name to app: $app_name"
    cf bind-service "$app_name" "$service_name"

    echo_step "Starting app with bound service"
    cf start "$app_name"

    # Wait a moment for the binding to be fully effective
    sleep 5
}

get_credentials_from_app() {
    local app_name=$1
    local temp_file=$(mktemp)

    # Print status to stderr so it doesn't get captured in command substitution
    echo_step "Extracting credentials from app: $app_name" >&2

    # Save the env output to a temporary file for processing
    cf env "$app_name" > "$temp_file"

    # Extract service credentials - this is the tricky part
    # We need to find the VCAP_SERVICES section and extract RabbitMQ credentials

    # Process the env output to extract dashboard_url
    # The dashboard_url appears between "dashboard_url": and the next comma or closing brace
    API_URL=$(grep -o '"dashboard_url": "[^"]*' "$temp_file" | head -1 | cut -d'"' -f4 | sed 's/\/#\//\/api\//')
    USERNAME=$(grep -o '"username": "[^"]*' "$temp_file" | head -1 | cut -d'"' -f4)
    PASSWORD=$(grep -o '"password": "[^"]*' "$temp_file" | head -1 | cut -d'"' -f4)

    # Clean up
    rm -f "$temp_file"

    echo "$API_URL"
    echo "$USERNAME"
    echo "$PASSWORD"
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



echo_step "Creating service instances that will be bound to apps (no service keys)..."

# Alpha Org - No service key, use app binding
cf target -o "test-org-alpha" -s "qa"
create_service_without_key "rabbitmq-alpha-app-bound"

APP_DIR=$(create_dummy_app "dummy-alpha-app")
push_and_bind_app "$APP_DIR" "dummy-alpha-app" "rabbitmq-alpha-app-bound"

CREDS=$(get_credentials_from_app "dummy-alpha-app")
API_URL_ALPHA=$(echo "$CREDS" | sed -n '1p')
USERNAME_ALPHA=$(echo "$CREDS" | sed -n '2p')
PASSWORD_ALPHA=$(echo "$CREDS" | sed -n '3p')

echo_step "Setting up mirrored queue policy in test-org-alpha (app-bound instance)"
curl -u "$USERNAME_ALPHA:$PASSWORD_ALPHA" "$API_URL_ALPHA/policies/%2f/ha-policy-app" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d '{
        "pattern": "^appbound-mirror.*",
        "definition": {
            "ha-mode": "exactly",
            "ha-params": 2,
            "ha-sync-mode": "automatic"
        }
    }'

rm -rf "$APP_DIR"

# Beta Org - No service key, use app binding
cf target -o "test-org-beta" -s "dev"
create_service_without_key "rabbitmq-beta-app-bound"

APP_DIR=$(create_dummy_app "dummy-beta-app")
push_and_bind_app "$APP_DIR" "dummy-beta-app" "rabbitmq-beta-app-bound"

CREDS=$(get_credentials_from_app "dummy-beta-app")
API_URL_BETA=$(echo "$CREDS" | sed -n '1p')
USERNAME_BETA=$(echo "$CREDS" | sed -n '2p')
PASSWORD_BETA=$(echo "$CREDS" | sed -n '3p')

echo_step "Setting up mirrored queue policy in test-org-beta (app-bound instance)"
curl -u "$USERNAME_BETA:$PASSWORD_BETA" "$API_URL_BETA/policies/%2f/ha-policy-app-beta" \
    -X PUT \
    -H "Content-Type: application/json" \
    -d '{
        "pattern": "^appbound-beta.*",
        "definition": {
            "ha-mode": "all",
            "ha-sync-mode": "automatic"
        }
    }'

rm -rf "$APP_DIR"

echo_success "Setup complete! Created:"
echo "- 3 organizations with 2 spaces each"
echo "- RabbitMQ instances with service keys:"
echo "  * Mirrored queues in test-org-alpha (pattern: ^mirror.*)"
echo "  * Mirrored queues in test-org-beta (pattern: ^beta.*)"
echo "  * Modern quorum queues in test-org-gamma (pattern: ^q.*)"
echo "- RabbitMQ instances with app bindings (no service keys):"
echo "  * Mirrored queues in test-org-alpha/qa (pattern: ^appbound-mirror.*)"
echo "  * Mirrored queues in test-org-beta/dev (pattern: ^appbound-beta.*)"



