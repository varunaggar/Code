# Project - ORI19

Azure Cosmos DB + Azure Functions (PowerShell) for mailbox metadata ingestion.

## Structure
- `infra/` Bicep for Cosmos account, DB, containers
- `scripts/` deploy scripts
- `schemas/` JSON data contracts
- `ingest/` seed CSV + verification scripts
- `functions/` Azure Functions app (HTTP + Timer)

## Prerequisites
- Azure CLI and Functions Core Tools
- Cosmos DB account + master key (or use SDK/managed identity)

## Deploy Cosmos
```bash
cd "Project - ORI19/scripts"
./deploy-cosmos.sh <rg> <location> <accountName> [databaseName]
```

## Local Settings
Update `functions/local.settings.json` values:
- `COSMOS_MASTER_KEY`, `TENANT_ID`, `GEO`

## Run Functions Locally
```bash
cd "Project - ORI19/functions"
func start
```

### HTTP Ingest
```bash
curl -s -X POST \
  "http://localhost:7071/api/ingest/mailboxes" \
  -H "Content-Type: application/json" \
  -d '[{"primarySmtpAddress":"alice@example.com","userPrincipalName":"alice@example.com","exchangeGuid":"1f1d2e3f-4a5b-6c7d-8e9f-001122334455","externalDirectoryObjectId":"11111111-2222-3333-4444-555555555555"}]'
```

### Timer Ingest
- Uses `SEED_CSV_PATH` to upsert from `ingest/mailboxes-seed.csv` hourly.

### Verify Docs
```powershell
pwsh -File "Project - ORI19/ingest/Verify-Mailboxes.ps1" \ 
  -AccountName <account> -DatabaseName mailboxdb -ContainerName Mailboxes -MasterKey <key>
```

## Notes
- For production, prefer Cosmos SDK/managed identity over raw REST.
- Partition keys: `/mailboxId` for operational containers; `/tenantId` for audit logs.

## Deploy to Azure (CLI)
```bash
cd "Project - ORI19/scripts"
# Deploy Function App (Premium)
./deploy-functions.sh <subscriptionId> <rg> <location> <functionAppName> <planName>

# Publish functions (from local machine)
cd ../functions
func azure functionapp publish <functionAppName>

# Wire Event Grid to HTTP ingest function
cd ../scripts
./wire-eventgrid.sh <subscriptionId> <rg> <functionAppName> MailboxIngestHttp \
  <sourceResourceId> eg-sub-mailbox-ingest
```
