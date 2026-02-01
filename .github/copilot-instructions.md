# Copilot instructions for this repository

Purpose
- Provide concise, actionable guidance so an AI coding agent can be productive in this mixed-language mono-repo.

Big picture
- This repo contains several largely independent components:
  - PowerShell automation and Graph/Exchange tooling under `Powershell/` (primary operational scripts).
  - Python utilities and small scripts under `Python/` (data-processing, helpers).
  - Terraform infra under `Terraform/` (Azure resources; uses provider alias `azurerm.Main` in `main.tf`).
  - macOS/Swift sample apps under `Swift/` and Xcode projects at `Hello World/`.
  - Misc Android examples under `Android/` and small C/C++ snippets under `C/`.

Key patterns & conventions (do not assume defaults)
- PowerShell scripts commonly source an untracked `psvariables.ps1` for secrets/config. Example: `Powershell/Generic/GraphClientCredentials.ps1` and `Powershell/Generic/Graph.ps1`.
- Authentication flows:
  - Client credential flow uses MSAL in `GraphClientCredentials.ps1` and expects `$AppIDGraphApplication` / secret values in `psvariables.ps1`.
  - Delegated flows appear in `GraphDelegated.ps1` (use `/me` vs `/users/{id}` differences).
- Logging: scripts use `Start-FastLog` / `Write-FastLog` from `Modules/Common`. Prefer using these helpers rather than ad-hoc Write-Host.
- Graph calls: prefer using helper `Invoke-GraphAPI` pattern shown in `GraphClientCredentials.ps1`.
- Terraform uses explicit commands in comments in `Terraform/main.tf` (e.g., `terraform plan -out tfplan`, `terraform fmt`, `terraform validate`).

How to run common workflows
- Run a PowerShell script (macOS requires PowerShell Core):
  - `pwsh -File Powershell/Generic/GraphClientCredentials.ps1`
  - Ensure `Powershell/Generic/psvariables.ps1` exists or provide equivalent environment variables.
- Python scripts:
  - Create venv and install deps if present: `python -m venv .venv && source .venv/bin/activate && pip install -r Python/requirements.txt`.
  - Example runner: `python Python/graph_delegated.py`.
- Terraform:
  - `cd Terraform && terraform init && terraform plan -out=tfplan && terraform apply tfplan`.
- Xcode/Swift: open the Xcode workspace/project in Xcode for local builds; tests run via Xcode or `xcodebuild` for CI.

Integration & external dependencies
- Graph API / Azure AD: many PowerShell scripts call Microsoft Graph — expect tenant/client secrets, MSAL assemblies, and granted API permissions. See `Powershell/Generic/GraphClientCredentials.ps1` for required variables and error hints.
- Local secrets: `psvariables.ps1` is intentionally untracked; do NOT hardcode secrets in new commits. Use environment variables or a secure vault.
- Terraform state: repo contains `terraform.tfstate` and related. Be cautious editing stateful files.

When editing or adding scripts
- Reuse `Modules/Common` helpers for logging and shared functions.
- Preserve the `psvariables.ps1` pattern; if adding a new script that needs secrets, make it tolerant when `psvariables.ps1` is missing and document required variables at the top of the script.

Examples in-repo to reference
- PowerShell token+Graph example: `Powershell/Generic/GraphClientCredentials.ps1`
- Graph REST quick token: `Powershell/Generic/Graph.ps1`
- Python data example: `Python/graph_delegated.py`
- Terraform layout: `Terraform/main.tf`

If unsure
- Run small, non-destructive commands first (list/read-only Graph endpoints, `terraform plan`, `pwsh -WhatIf` where supported).
- Ask for clarification on missing env/secret values before making changes that require live credentials.

If this file is incomplete or you want more detail (build commands, CI, or common refactors) tell me which component to expand.
