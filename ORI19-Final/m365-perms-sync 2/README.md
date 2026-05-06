# M365 Permissions Sync

Azure Functions–based solution that maintains a SQL database of M365 Exchange Online mailbox permissions, kept in sync with the tenant.

This is a phased build. The current phase covers **user information sync** — the foundational table that every later layer (mailboxes, permissions, group memberships) builds on.

---

## Project structure

```
m365-perms-sync/
├── README.md                       # This file
├── host.json                       # Function App runtime config
├── profile.ps1                     # Worker startup — imports shared helpers
├── requirements.psd1               # Module dependencies (Az.Accounts, Az.KeyVault)
├── .gitignore
│
├── shared/                         # Reusable PowerShell modules
│   ├── GraphHelpers.psm1           # ✅ DONE — Graph REST helpers
│   ├── SqlHelpers.psm1             # ✅ DONE — database helpers
│   └── LoggingHelpers.psm1         # ✅ DONE — App Insights telemetry
│
├── sql/                            # Database schema (deploy in order)
│   ├── 01_shared_tables.sql        # ✅ DONE — DeltaTokens, SyncLog
│   ├── 02_users_table.sql          # ✅ DONE — Users
│   └── (future: mailboxes, permissions, etc.)
│
├── Invoke-UserBaselineLoad/        # ✅ DONE — HTTP-triggered, runs once
│   ├── function.json
│   └── run.ps1
│
├── Invoke-UserDeltaSync/           # ✅ DONE — Timer-triggered, every 15 min
│   ├── function.json
│   └── run.ps1
│
├── docs/                           # Architecture / decisions / runbooks
│
└── .github/workflows/              # ⏳ TODO — CI/CD pipeline
    └── deploy.yml
```

---

## Architecture decisions made

| Area | Choice | Rationale |
|---|---|---|
| Compute | Azure Functions (PowerShell, Linux) | Better observability and developer experience than Automation runbooks |
| Graph access | Raw REST via `Invoke-RestMethod` | Lower cold-start cost, cleaner delta query handling |
| Change detection | Graph `/users/delta` query, 15-min polling | Simpler than change notifications, automatic gap recovery |
| Authentication | System-assigned Managed Identity → Key Vault → Graph app credentials | Zero stored credentials |
| Database | Azure SQL (Serverless tier — Phase 1) | Cost-efficient; will scale to Hyperscale when permissions added |
| Primary key | Entra `id` (Object GUID) | Immutable; UPNs change but Object IDs never do |
| Deletion | Soft-delete (`IsDeleted=1`, `DeletedAt`) | Preserves history for permission attribution |

---

## Phase 1 — User information sync (current)

Two processes:

**`Invoke-UserBaselineLoad`** — HTTP-triggered, runs once on initial deployment.
Pages through `/users`, upserts every user, then initiates `/users/delta` to capture
a starting delta token.

**`Invoke-UserDeltaSync`** — Timer-triggered, every 15 minutes.
Reads stored delta token, calls `/users/delta`, processes only changes (new, modified,
deleted), advances the token. Handles HTTP 410 (token expired) by deactivating the
token and requiring a baseline re-run.

### Three SQL tables

- **`Users`** — destination table for user data
- **`DeltaTokens`** — stores delta cursor positions (one row per source)
- **`SyncLog`** — operational tracking (one row per function execution)

### Estimated cost — Phase 1

~£25–40/month on UK South pay-as-you-go.
SQL Serverless dominates (~£20). Functions, Storage, App Insights round to ~£10.

---

## Common Azure infrastructure (12 objects)

Deploy these once as the foundation:

1. Resource Group
2. Entra app registration (M365 Permissions Sync)
3. Key Vault (secrets: TenantId, GraphAppId, GraphAppSecret)
4. Azure SQL Database (Serverless, 2 vCore)
5. Shared SQL tables (`01_shared_tables.sql`, `02_users_table.sql`)
6. Storage Account
7. Log Analytics Workspace + Application Insights
8. Function App (Consumption plan, PS 7.4, Linux)
9. System-assigned Managed Identity on Function App
10. RBAC: Key Vault Secrets User + SQL db_datareader/writer
11. Action Group for alerts
12. Function App project structure (this folder)

---

## Operational sequence (once everything is deployed)

1. Deploy 12 common objects
2. Run `01_shared_tables.sql` then `02_users_table.sql` against the database
3. Deploy Function App code from this repo (`func azure functionapp publish func-m365perms-prod`)
4. **Manually invoke `Invoke-UserBaselineLoad`** — takes 10–30 min, writes 40K users, captures starting delta token
5. **Enable timer schedule on `Invoke-UserDeltaSync`** — runs every 15 min thereafter
6. Monitor via SyncLog table and App Insights KQL

---

## What's next

Phase 1 code is complete. Remaining work to put it into production:

1. ⏳ **Deploy the 12 common Azure objects** (Resource Group, Entra app, Key Vault, SQL DB, Storage, App Insights, Function App, Managed Identity, RBAC, Action Group, Log Analytics)
2. ⏳ **Run SQL scripts** against the database in order (`01_shared_tables.sql`, then `02_users_table.sql`)
3. ⏳ **Deploy Function App code** from this repo (`func azure functionapp publish func-m365perms-prod`)
4. ⏳ **Manually invoke** `Invoke-UserBaselineLoad` via its HTTP endpoint
5. ⏳ **Verify** the timer-triggered `Invoke-UserDeltaSync` runs successfully on its schedule
6. ⏳ **Configure monitoring alerts** (sync staleness, runbook failures, token expiry)
7. ⏳ **(Optional)** Bicep IaC template to automate the 12 common objects

After Phase 1 is validated end-to-end, we move on to **mailbox sync** (all five mailbox types — UserMailbox, SharedMailbox, RoomMailbox, EquipmentMailbox, GroupMailbox).

---

## Required Function App environment variables

Set these in the Function App's Configuration → Application settings before deployment:

| Variable | Value |
|---|---|
| `KEY_VAULT_NAME` | e.g. `kv-m365perms-prod` |
| `SQL_SERVER` | e.g. `sql-m365perms-prod.database.windows.net` |
| `SQL_DATABASE` | e.g. `db-m365permissions` |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | (set automatically when AI is linked) |
| `FUNCTIONS_WORKER_RUNTIME` | `powershell` (set automatically) |
