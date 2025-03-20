#!/usr/bin/env bash

set -euo pipefail

echo "Setting up mirrored queue policies for app-bound instance in test-org-alpha/qa"
cf target -o test-org-alpha -s qa

ENV_FILE=$(mktemp)
cf env dummy-alpha-app > "$ENV_FILE"

HTTP_API_URI=$(grep -o '"http_api_uri": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)
VHOST=$(grep -o '"vhost": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)
USERNAME=$(grep -o '"username": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)
PASSWORD=$(grep -o '"password": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)

ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

# Create a test queue with the appropriate pattern to match the policy
echo "Creating test queues that match the mirroring pattern..."
curl -i -u "$USERNAME:$PASSWORD" -X PUT "${HTTP_API_URI}queues/${ENCODED_VHOST}/appbound-mirror.test.queue" \
    -H "content-type: application/json" \
    -d '{
        "durable": true
    }'

# Create another test queue
curl -i -u "$USERNAME:$PASSWORD" -X PUT "${HTTP_API_URI}queues/${ENCODED_VHOST}/appbound-mirror.important.queue" \
    -H "content-type: application/json" \
    -d '{
        "durable": true
    }'

# Create the mirroring policy for the app-bound alpha instance
echo "Creating mirroring policy for app-bound instance in test-org-alpha..."
curl -i -u "$USERNAME:$PASSWORD" -X PUT "${HTTP_API_URI}policies/${ENCODED_VHOST}/ha-policy-appbound" \
    -H "content-type: application/json" \
    -d '{
        "pattern": "^appbound-mirror.*",
        "definition": {
            "ha-mode": "all",
            "ha-sync-mode": "automatic"
        },
        "priority": 1,
        "apply-to": "queues"
    }'

rm -f "$ENV_FILE"

echo "Setting up mirrored queue policies for app-bound instance in test-org-beta/dev"
cf target -o test-org-beta -s dev

ENV_FILE=$(mktemp)
cf env dummy-beta-app > "$ENV_FILE"

HTTP_API_URI=$(grep -o '"http_api_uri": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)
VHOST=$(grep -o '"vhost": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)
USERNAME=$(grep -o '"username": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)
PASSWORD=$(grep -o '"password": "[^"]*' "$ENV_FILE" | head -1 | cut -d'"' -f4)

ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

echo "Creating test queues that match the mirroring pattern..."
curl -i -u "$USERNAME:$PASSWORD" -X PUT "${HTTP_API_URI}queues/${ENCODED_VHOST}/appbound-beta.test.queue" \
    -H "content-type: application/json" \
    -d '{
        "durable": true
    }'

curl -i -u "$USERNAME:$PASSWORD" -X PUT "${HTTP_API_URI}queues/${ENCODED_VHOST}/appbound-beta.metrics.queue" \
    -H "content-type: application/json" \
    -d '{
        "durable": true
    }'

echo "Creating mirroring policy for app-bound instance in test-org-beta..."
curl -i -u "$USERNAME:$PASSWORD" -X PUT "${HTTP_API_URI}policies/${ENCODED_VHOST}/ha-policy-beta-appbound" \
    -H "content-type: application/json" \
    -d '{
        "pattern": "^appbound-beta.*",
        "definition": {
            "ha-mode": "all",
            "ha-sync-mode": "automatic"
        },
        "priority": 1,
        "apply-to": "queues"
    }'

rm -f "$ENV_FILE"

echo "Setup complete! Created mirrored queue policies for app-bound instances."