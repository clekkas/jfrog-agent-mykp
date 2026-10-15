---
name: "Apply Platform Contract"
description: "Update the agent deployment environment and configuration to utilize the foundation platform contract (foundry-<env>.json)"
argument-hint: "Path to an approved published contract matching mysecond-project-for-kp"
agent: "agent"
---

# Apply Platform Contract to Agent Deployment

You are updating platform variables in this repository's protected `agent` environment from an approved, matching-project contract. Do not change the deployment target or deploy an agent as part of this operation.

## Background & Architecture

This **application repo** is independently bootstrapped but depends on foundation-owned registry, state, and runner infrastructure. Bootstrap sets its target to `mysecond-project-for-kp`. Contract imports are an optional update path, not a requirement for initial setup.

**The foundation currently publishes a dev contract for `workshop-demo-project`, not this project. No matching mykp contract is currently published.** If only the dev artifact is available, stop and report the missing matching-project prerequisite. Do not alter target fields and recompute its checksum.

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
1. Obtain the user-specified contract and verify its source workflow/artifact is approved. A valid checksum alone is not proof of provenance.
2. Confirm it targets this project's existing `agent` environment, not the workshop project.
3. Confirm bootstrap has already initialized the environment. Do not initialize or retarget it from the artifact.

### 2. Update GitHub Environment Variables
Use only the guarded importer. It validates version, required string values, canonical checksum, internal project fields, and the existing destination before any writes:
```powershell
./scripts/import-platform-contract.ps1 -ContractPath "<approved-matching-project-contract.json>" -Repo "clekkas/jfrog-agent-mykp" -Environment "agent"
```
Never use bulk `gh variable set` loops or manual target overrides to bypass a failed validation. App-owned deployment identities and state settings are not contract inputs.

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

### 4. Report the Result
Report the matched project and verified checksum, or the specific validation failure. Do not start runner VMs or trigger deployment automatically.

On a separately approved release, the workflow verifies the immutable image, creates a session pinned to the candidate version, and checks execution provenance. Model mode requires the expected deployment and upstream model response ID; a completed scope-blocked or echo response is not sufficient.
