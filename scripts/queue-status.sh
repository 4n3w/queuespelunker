#!/usr/bin/env bash

set -euo pipefail

source colours.sh

verify_queue() {
    local api_uri=$1
    local vhost=$2
    local queue=$3
    
    # URL encode the vhost
    local encoded_vhost=$(echo -n "$vhost" | jq -sRr @uri)
    
    echo -e "${BLUE}==> Checking queue $queue in vhost $vhost...${NC}"
    
    # Get queue details including policy and mirroring status
    curl -s "${api_uri}queues/${encoded_vhost}/${queue}" | jq '
        {
            name: .name,
            policy: .policy,
            type: .type,
            slave_nodes: .slave_nodes,
            synchronised_slave_nodes: .synchronised_slave_nodes,
            node: .node
        }'
}

# Example usage (you'll need to fill in these values from your service key):
API_URI="https://user:pass@rmq-instance.domain.tld/api/"
VHOST="generally_matches_service_instance_guid"
verify_queue "$API_URI" "$VHOST" "beta.test.queue"
