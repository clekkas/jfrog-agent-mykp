# GitHub Copilot Instructions for jfrog-agent-mykp

This repository deploys the `mykp-hosted-agent` hosted agent to Microsoft Foundry using container images stored in a private JFrog Artifactory registry.

## Contract-Driven Architecture

This repository is **application-only** and does NOT manage cloud infrastructure or registry connections directly:
- The private JFrog OIDC connection (`jfrog-registry-acct`) is provisioned and managed centrally by the foundation repository (`jfrog-oidc-foundry`).
- Project deployment variables are initially set by this repo's bootstrap, using foundation-owned shared infrastructure.
- Approved **Platform Contract** updates may be imported into the protected `agent` environment only when they match its existing project.
- The current foundation dev contract targets `workshop-demo-project` and is not valid here. A matching mykp contract is not currently published.

## Deployment Guidelines

1. **Do Not Hardcode Registry Credentials:**
   - Image pushes from GitHub Actions authenticate to JFrog using GitHub OIDC (`JFROG_GITHUB_OIDC_PROVIDER`).
   - Image pulls by Foundry authenticate to JFrog using Entra ID OIDC token exchange via the shared connection `jfrog-registry-acct`.
2. **Consuming Contract Changes:**
   - To adapt the deployment to a new or updated platform contract, run the prompt action:
     `/apply-platform-contract` (defined in `.github/prompts/apply-platform-contract.prompt.md`)
   - Or use `scripts/import-platform-contract.ps1 -ContractPath <matching-published-contract>`.
   - The importer verifies schema/checksum and the existing environment's full project tuple before any writes. Never bypass it with bulk variable-copy commands or edit/re-hash a mismatched artifact.
3. **Terraform Scope:**
   - `infra/hosted-agent/` only manages the data-plane resource `azapi_data_plane_resource.hosted_agent`.
   - `container_configuration.registry_connection_id` must reference `${TF_VAR_registry_connection_name}` (which resolves to `jfrog-registry-acct`).
   - It maintains state in its own isolated container (`agent-tfstate-mykp`) and never accesses the foundation repository's state.
4. **Release Validation:**
   - Smoke tests create a session pinned to the exact candidate version; never change public routing to test a release.
   - Model mode requires execution metadata from a successful model call, including deployment and upstream response ID. Echo mode must be explicitly configured; blocked/lookup replies are not model evidence.
