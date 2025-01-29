#!/usr/bin/env bash

set -euo pipefail

source colours.sh

echo -e "${BLUE}==> Getting service key...${NC}"
CREDS=$(cf service-key rabbitmq-beta-qa admin-key | awk 'NR>2')
echo -e "${BLUE}==> Credentials retrieved${NC}"

API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.vhost')

echo -e "${BLUE}==> API URI: ${NC}$API_URI"
echo -e "${BLUE}==> VHOST: ${NC}$VHOST"

ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)
echo -e "${BLUE}==> Encoded VHOST: ${NC}$ENCODED_VHOST"

create_queue() {
    local queue_name=$1
    echo -e "${BLUE}==> Creating queue: $queue_name${NC}"
    echo -e "${BLUE}==> Using URL: ${API_URI}queues/${ENCODED_VHOST}/${queue_name}${NC}"
    
    curl -i -X PUT "${API_URI}queues/${ENCODED_VHOST}/${queue_name}" \
        -H "content-type: application/json" \
        -d '{
            "durable": true,
            "auto_delete": false
        }'
    echo
}

echo -e "${BLUE}==> Creating test queues...${NC}"

# Should be mirrored (match ^beta.*)
create_queue "beta.important.queue"
create_queue "beta.critical.queue"
create_queue "beta.metrics.queue"

# Should not be mirrored
create_queue "important.queue"
create_queue "testing.queue"

echo -e "${GREEN}==> Queues created${NC}"

echo -e "${BLUE}==> Listing current queues in vhost:${NC}"
curl -s "${API_URI}queues/${ENCODED_VHOST}" | jq -r '.[].name'
