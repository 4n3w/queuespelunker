#!/usr/bin/env bash

set -euo pipefail

CREDS=$(cf service-key rabbitmq-beta-qa admin-key | tail -n +3)
API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')

echo "Checking cluster status..."
curl -s "${API_URI}nodes" | jq '.'
