#!/usr/bin/env bash

set -euo pipefail

source colours.sh

check_cluster() {
    local api_uri=$1
    
    echo -e "${BLUE}==> Checking cluster status...${NC}"
    curl -s "${api_uri}cluster-name" | jq '.'
    
    echo -e "${BLUE}==> Checking nodes in cluster...${NC}"
    curl -s "${api_uri}nodes" | jq '.'
}

# Example usage (you'll need to fill in these values from your service key):
API_URI="https://user:pass@rmq-instance.domain.tld/api/"
check_cluster "$API_URI"
