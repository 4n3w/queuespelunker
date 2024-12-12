#!/usr/bin/env bash

set -euo pipefail

CREDS=$(cf service-key rabbitmq-alpha-qa admin-key | tail -n +3)
API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.vhost')

ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

echo "Creating policy for vhost: $VHOST"
echo "Using API URI: $API_URI"

# Create policy with correct vhost
curl -i -X PUT "${API_URI}policies/${ENCODED_VHOST}/ha-policy-alpha" \
    -H "content-type: application/json" \
    -d '{
        "pattern": "^alpha.*",
        "definition": {
            "ha-mode": "all",
            "ha-sync-mode": "automatic"
        },
        "priority": 1,
        "apply-to": "queues"
    }'

echo -e "\nVerifying policy creation:"
curl -s "${API_URI}policies" | jq '.'

