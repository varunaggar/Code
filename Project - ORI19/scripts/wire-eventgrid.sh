#!/usr/bin/env zsh
set -euo pipefail

# Usage: ./wire-eventgrid.sh <subscriptionId> <resourceGroup> <functionAppName> <functionName> <sourceResourceId> <subscriptionName>
SUB=${1:?"subscription id required"}
RG=${2:?"resource group required"}
APP=${3:?"function app name required"}
FUNC=${4:?"function name required"}
SRC=${5:?"event grid source resource id required"}
SUBNAME=${6:?"event subscription name required"}

az account set --subscription "$SUB"

FUNC_URL=$(az functionapp function show -g "$RG" -n "$APP" --function-name "$FUNC" --query invokeUrlTemplate -o tsv)
if [ -z "$FUNC_URL" ]; then
  echo "Function URL not found. Ensure the function is published." >&2
  exit 1
fi

az eventgrid event-subscription create \
  --name "$SUBNAME" \
  --source-resource-id "$SRC" \
  --endpoint "$FUNC_URL" | cat

echo "Event Grid wired: $SUBNAME -> $FUNC_URL"