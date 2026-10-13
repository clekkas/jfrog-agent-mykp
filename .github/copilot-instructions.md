# GitHub Copilot Instructions for jfrog-agent-mykp

This repository deploys the `mykp-hosted-agent` hosted agent to Microsoft Foundry using container images stored in a private JFrog Artifactory registry.

## Contract-Driven Architecture

This repository is **application-only** and does NOT manage cloud infrastructure or registry connections directly:
- The private JFrog OIDC connection (`jfrog-registry-acct`) is provisioned and managed centrally by the foundation repository (`jfrog-oidc-foundry`).
- Platform configuration (registry URL, repository key, OIDC provider names, token audience, endpoints) is provided via a **Platform Contract** (`foundry-<env>.json`).
- These contract values are ingested as GitHub Environment variables on the protected `agent` environment.

## Deployment Guidelines

1. **Do Not Hardcode Registry Credentials:**
   - Image pushes from GitHub Actions authenticate to JFrog using GitHub OIDC (`JFROG_GITHUB_OIDC_PROVIDER`).
   - Image pulls by Foundry authenticate to JFrog using Entra ID OIDC token exchange via the shared connection `jfrog-registry-acct`.
2. **Consuming Contract Changes:**
   - To adapt the deployment to a new or updated platform contract, run the prompt action:
     `/apply-platform-contract` (defined in `.github/prompts/apply-platform-contract.prompt.md`)
   - Or use the script `scripts/import-platform-contract.ps1`.
3. **Terraform Scope:**
   - `infra/hosted-agent/` only manages the data-plane resource `azapi_data_plane_resource.hosted_agent`.
   - `container_configuration.registry_connection_id` must reference `${TF_VAR_registry_connection_name}` (which resolves to `jfrog-registry-acct`).
   - It maintains state in its own isolated container (`agent-tfstate-mykp`) and never accesses the foundation repository's state.
