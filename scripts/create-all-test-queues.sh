#!/usr/bin/env bash

set -euo pipefail

source colours.sh

echo "Setting up alpha instance queues..."
cf target -o test-org-alpha -s dev
CREDS=$(cf service-key rabbitmq-alpha-dev admin-key | tail -n +3)
API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.vhost')
ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

# Create alpha queues
for queue in "mirror.important.queue" "mirror.critical.queue" "mirror.metrics.queue" "important.queue" "testing.queue"; do
    echo -e "${BLUE}Creating queue: $queue${NC}"
    curl -i -X PUT "${API_URI}queues/${ENCODED_VHOST}/${queue}" \
        -H "content-type: application/json" \
        -d '{"durable": true, "auto_delete": false}'
done

echo "Setting up beta instance queues..."
cf target -o test-org-beta -s qa
CREDS=$(cf service-key rabbitmq-beta-qa admin-key | tail -n +3)
API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.vhost')
ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

# Create beta queues
for queue in "beta.important.queue" "beta.critical.queue" "beta.metrics.queue" "important.queue" "testing.queue"; do
    echo -e "${BLUE}Creating queue: $queue${NC}"
    curl -i -X PUT "${API_URI}queues/${ENCODED_VHOST}/${queue}" \
        -H "content-type: application/json" \
        -d '{"durable": true, "auto_delete": false}'
done

echo "Setting up gamma instance queues..."
cf target -o test-org-gamma -s dev
CREDS=$(cf service-key rabbitmq-gamma-dev admin-key | tail -n +3)
API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.vhost')
ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

# Create gamma queues (only non-mirrored/negative test cases)
for queue in "important.queue" "testing.queue"; do
    echo -e "${BLUE}Creating queue: $queue${NC}"
    curl -i -X PUT "${API_URI}queues/${ENCODED_VHOST}/${queue}" \
        -H "content-type: application/json" \
        -d '{"durable": true, "auto_delete": false}'
done

echo -e "${GREEN}All queues created${NC}"
