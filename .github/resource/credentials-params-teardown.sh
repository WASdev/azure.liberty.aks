#!/usr/bin/env bash
# Copyright (c) IBM Corporation.
# Copyright (c) Microsoft Corporation.

set -Eeuo pipefail

CURRENT_FILE_NAME=$(basename "$0")
echo "Execute $CURRENT_FILE_NAME - Start------------------------------------------"

# remove param the json
yq eval -o=json '.[]' "$param_file" | jq -c '.' | while read -r line; do
    name=$(echo "$line" | jq -r '.name')
    value=$(echo "$line" | jq -r '.value')
    gh secret remove "$name"
done

echo "Execute $CURRENT_FILE_NAME - End--------------------------------------------"
