---
name: "Apply Platform Contract"
description: "Update the agent deployment environment and configuration to utilize the foundation platform contract (foundry-<env>.json)"
argument-hint: "Environment name (e.g. dev) or path to contract file"
agent: "agent"
---

# Apply Platform Contract to Agent Deployment

You are updating this repository's deployment pipeline to utilize the platform contract published by `jfrog-oidc-foundry`.

## Background & Architecture

This repository is an **application repo** that deploys a hosted agent to Microsoft Foundry. It does NOT own the container registry connection or the Foundry account foundation. Instead, it consumes approved platform values published by `jfrog-oidc-foundry` via a **Platform Contract** (`foundry-<env>.json`).

The platform contract provides:
- `JFROG_REGISTRY_CONNECTION_NAME`: The shared connection name (e.g., `jfrog-registry-acct`).
- `JFROG_REGISTRY_CONNECTION_ID`: The full Azure ARM resource ID of the connection.
- `JF_URL`: JFrog instance origin (e.g., `https://trialndswdc.jfrog.io`).
- `JFROG_REPO`: Docker repository key in JFrog (e.g., `byor-demo-docker`).
- `JFROG_GITHUB_OIDC_PROVIDER`: JFrog OIDC provider for GitHub Actions pushes.
- `REGISTRY_TOKEN_AUDIENCE`: Entra ID token audience for image pulls.
- `REGISTRY_TOKEN_ENDPOINT`: JFrog token exchange endpoint (`/access/api/v1/oidc/token`).
- `REGISTRY_OIDC_PROVIDER_NAME`: JFrog OIDC provider name for Entra ID pulls (`oidc-byor`).
- Azure & Foundry identifiers: `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `FOUNDRY_ACCOUNT_NAME`.

## Steps to Execute

### 1. Locate and Validate Contract
1. Check if `foundry-<env>.json` (e.g., `foundry-dev.json`) exists in the repository root.
2. If not found or updating to the latest, download the latest artifact from `jfrog-oidc-foundry`:
   ```bash
   gh run download --repo clekkas/jfrog-oidc-foundry -n platform-contract-<env> -D .
   ```
3. Verify the checksum:
   ```bash
   test "$(jq -S -c .values foundry-<env>.json | sha256sum | cut -d' ' -f1)" = "$(jq -r .valuesSha256 foundry-<env>.json)" && echo "Contract checksum OK"
   ```

### 2. Update GitHub Environment Variables
Update the protected `agent` GitHub Environment variables to match the values from the contract.
Run `scripts/import-platform-contract.ps1`:
```powershell
./scripts/import-platform-contract.ps1 -ContractPath "foundry-dev.json" -Repo "clekkas/jfrog-agent-mykp" -Environment "agent"
```
Or set them individually with the GitHub CLI:
```bash
jq -r '.values | to_entries[] | [.key, .value] | @tsv' foundry-dev.json | while IFS=$'\t' read -r k v; do
  gh variable set "$k" --repo clekkas/jfrog-agent-mykp --env agent --body "$v"
done
```

### 3. Verify Deployment Terraform & Workflow
Ensure the deployment files in this repo properly wire the contract variables:
- In `.github/workflows/deploy-agent.yml`:
  - `TF_VAR_registry_connection_name: ${{ vars.JFROG_REGISTRY_CONNECTION_NAME }}`
  - `JF_URL: ${{ vars.JF_URL }}`
  - `JFROG_REPO: ${{ vars.JFROG_REPO }}`
  - `JFROG_GITHUB_OIDC_PROVIDER: ${{ vars.JFROG_GITHUB_OIDC_PROVIDER }}`
- In `infra/hosted-agent/main.tf`:
  - `container_configuration.registry_connection_id = var.registry_connection_name`
- In `scripts/bootstrap-github-oidc.ps1`:
  - Ensure local defaults match the shared connection `jfrog-registry-acct`.

### 4. Trigger & Verify Deployment
1. Start the self-hosted runner VM if deallocated (`byor-ci-agent-runner-01`).
2. Trigger the deployment workflow:
   ```bash
   gh workflow run deploy-agent.yml --repo clekkas/jfrog-agent-mykp --ref main
   ```
3. Verify in the workflow run logs:
   - Image built and pushed to `<JF_URL host>/<JFROG_REPO>/agent-mykp`
   - Terraform modifies `azapi_data_plane_resource.hosted_agent` referencing `jfrog-registry-acct`
   - OIDC token exchange succeeds (no `exchange_failed` errors)
   - Smoke test passes (`status: completed`).
