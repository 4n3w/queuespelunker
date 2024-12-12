#!/usr/bin/env bash

set -euo pipefail

source colours.sh

echo -e "${BLUE}Creating 250 test orgs...${NC}"

for i in {1..250}; do
    org_name="test-org-$i"
    echo -e "${BLUE}Creating org: $org_name${NC}"
    cf create-org "$org_name" || true
    
    num_spaces=$((1 + RANDOM % 2))
    
    for j in $(seq 1 $num_spaces); do
        space_name="space-$j"
        echo -e "${BLUE}Creating space: $space_name in $org_name${NC}"
        cf target -o "$org_name" > /dev/null
        cf create-space "$space_name" || true
    done
    
    if (( i % 10 == 0 )); then
        echo -e "${GREEN}Progress: $i/250 organizations created${NC}"
    fi
done

echo -e "${GREEN}All organizations and spaces created${NC}"
