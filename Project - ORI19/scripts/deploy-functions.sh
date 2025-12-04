#!/usr/bin/env zsh
set -euo pipefail

# Usage: ./deploy-functions.sh <subscriptionId> <resourceGroup> <location> <functionAppName> <planName>
SUB=${1:?"subscription id required"}
RG=${2:?"resource group required"}
LOC=${3:?"location required"}
APP=${4:?"function app name required"}
PLAN=${5:?"plan name required"}

STOR="st${APP//-/}"
APPI="appi-${APP}"

az account set --subscription "$SUB"
az group create -n "$RG" -l "$LOC" | cat

az storage account create -n "$STOR" -g "$RG" -l "$LOC" --sku Standard_LRS | cat
az monitor app-insights component create -g "$RG" -l "$LOC" -a "$APPI" | cat

az functionapp plan create -g "$RG" -n "$PLAN" --location "$LOC" --min-instances 1 --max-burst 20 --sku EP1 | cat

az functionapp create -g "$RG" -n "$APP" -p "$PLAN" -s "$STOR" --runtime powershell --functions-version 4 --assign-identity | cat

# Configure app settings from local.settings.json if present
SETTINGS_FILE="$(cd -- "$(dirname "$0")/.." && pwd)/functions/local.settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  COSMOS_ACCOUNT=$(jq -r '.Values.COSMOS_ACCOUNT' "$SETTINGS_FILE")
  COSMOS_DB=$(jq -r '.Values.COSMOS_DB' "$SETTINGS_FILE")
  COSMOS_CONTAINER=$(jq -r '.Values.COSMOS_CONTAINER' "$SETTINGS_FILE")
  COSMOS_MASTER_KEY=$(jq -r '.Values.COSMOS_MASTER_KEY' "$SETTINGS_FILE")
  TENANT_ID=$(jq -r '.Values.TENANT_ID' "$SETTINGS_FILE")
  GEO=$(jq -r '.Values.GEO' "$SETTINGS_FILE")
  az functionapp config appsettings set -g "$RG" -n "$APP" --settings \
    "FUNCTIONS_WORKER_RUNTIME=powershell" \
    "COSMOS_ACCOUNT=$COSMOS_ACCOUNT" \
    "COSMOS_DB=$COSMOS_DB" \
    "COSMOS_CONTAINER=$COSMOS_CONTAINER" \
    "COSMOS_MASTER_KEY=$COSMOS_MASTER_KEY" \
    "TENANT_ID=$TENANT_ID" \
    "GEO=$GEO" | cat
fi

echo "Function App deployed: $APP"