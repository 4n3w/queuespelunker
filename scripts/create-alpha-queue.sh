#!/usr/bin/env bash

set -euo pipefail

source colours.sh

echo -e "${BLUE}==> Creating test queues for rabbitmq-alpha-dev...${NC}"

cf target -o test-org-alpha -s dev

CREDS=$(cf service-key rabbitmq-alpha-dev admin-key | awk 'NR>2')

API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.protocols.amqp.vhost')

ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

# Create queues that match our policy patterns
echo -e "${BLUE}==> Creating queue that should be mirrored (matches ^mirror.*) in vhost ${VHOST}${NC}"
curl -i -X PUT "${API_URI}queues/${ENCODED_VHOST}/mirror.test.queue" \
    -H "content-type: application/json" \
    -d '{"durable": true, "auto_delete": false}'

echo -e "${BLUE}==> Creating queue that should NOT be mirrored (doesn't match pattern)${NC}"
curl -i -X PUT "${API_URI}queues/${ENCODED_VHOST}/normal.test.queue" \
    -H "content-type: application/json" \
    -d '{"durable": true, "auto_delete": false}'

echo -e "${GREEN}==> Test queues created${NC}"
