#!/usr/bin/env bash

set -euo pipefail

cf target -o test-org-alpha -s dev
CREDS=$(cf service-key rabbitmq-alpha-dev admin-key | tail -n +3)
API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.vhost')
ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

# Create the mirroring policy for alpha instance
curl -i -X PUT "${API_URI}policies/${ENCODED_VHOST}/ha-policy" \
    -H "content-type: application/json" \
    -d '{
        "pattern": "^mirror.*",
        "definition": {
            "ha-mode": "all",
            "ha-sync-mode": "automatic"
        },
        "priority": 1,
        "apply-to": "queues"
    }'

