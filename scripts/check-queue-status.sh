#!/usr/bin/env bash

set -euo pipefail

CREDS=$(cf service-key rabbitmq-beta-qa admin-key | tail -n +3)
API_URI=$(echo "$CREDS" | jq -r '.http_api_uri')
VHOST=$(echo "$CREDS" | jq -r '.vhost')

ENCODED_VHOST=$(echo -n "$VHOST" | jq -sRr @uri)

echo "Checking queue status..."
curl -s "${API_URI}queues/${ENCODED_VHOST}/beta.test.queue" | jq '
{
    name: .name,
    policy: .policy,
    type: .type,
    slave_nodes: .slave_nodes,
    synchronised_slave_nodes: .synchronised_slave_nodes,
    node: .node,
    policy_name: .policy,
    arguments: .arguments,
    effective_policy_definition: .effective_policy_definition
}'
