#!/usr/bin/env zsh
set -euo pipefail

# Usage: ./deploy-cosmos.sh <resourceGroup> <location> <accountName> [databaseName]
RG=${1:?"resource group required"}
LOC=${2:?"location required"}
ACCOUNT=${3:?"cosmos account name required"}
DBNAME=${4:-mailboxdb}

SCRIPT_DIR=$(cd -- "$(dirname "$0")" && pwd)
INFRA_DIR="$SCRIPT_DIR/../infra"

az group create -n "$RG" -l "$LOC" | cat

az deployment group create \
  -g "$RG" \
  -f "$INFRA_DIR/cosmos.bicep" \
  -p accountName="$ACCOUNT" location="$LOC" databaseName="$DBNAME" | cat

echo "Cosmos deployment complete: account=$ACCOUNT db=$DBNAME"