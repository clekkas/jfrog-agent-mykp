# JFrog BYOR Agent for mykp

This repository deploys the `mykp-hosted-agent` hosted agent to the Foundry project `mysecond-project-for-kp`. It uses the same FastAPI Responses container and Terraform/AzAPI deployment pattern as `jfrog-agent-byor`, with a separate GitHub repository, deployment identity, and Terraform state container.

## Project

- Tenant: `16b3c013-d300-468d-ac64-7eda0820b6d3`
- Foundry account: `kaiser-foundry-resource`
- Project ID: `/subscriptions/0e494a0c-e2e6-41f8-8a50-6064d842225e/resourceGroups/kaiser-foundry-rg/providers/Microsoft.CognitiveServices/accounts/kaiser-foundry-resource/projects/mysecond-project-for-kp`
- Project endpoint: `https://kaiser-foundry-resource.services.ai.azure.com/api/projects/mysecond-project-for-kp`
- Model deployment: `gpt-5-mini`

This repository is self-contained: it needs nothing from `jfrog-oidc-foundry`. It uses the account-shared Foundry connection `jfrog-registry-acct` (visible from the project by name), the existing Terraform state account `tfstateb173d2d85c34` (own container), and a repo-scoped self-hosted runner. All project values are embedded in `scripts/bootstrap-github-oidc.ps1`.

## Local Checks

Install dependencies and run the container:

```powershell
python -m pip install -r requirements.txt
python -m uvicorn app:app --host 127.0.0.1 --port 8088
```

In another terminal, run the local Responses and health checks:

```powershell
python test_local.py
```

## CI/CD

`.github/workflows/deploy-agent.yml` follows the reference pipeline: build and smoke-test a `linux/amd64` image, push it to JFrog with GitHub OIDC, resolve its immutable digest, then deploy with Terraform from the self-hosted `byor-private` runner. This repo uses image name `agent-mykp` in the shared `byor-demo-docker` repository to avoid tag collisions with the reference repo. `agent-plan.yml` is manual and never applies.

The workflow uses the protected GitHub Environment `agent` in this repository. Bootstrap it with `./scripts/bootstrap-github-oidc.ps1 -Repo clekkas/jfrog-agent-mykp -NoRequiredReviewers` (separate state container `agent-tfstate-mykp`, key `hosted-agent/mykp.tfstate`). Backend config, Terraform plans, and state must not be committed.

Before deployment, confirm this Foundry project's managed identity is assigned to the `Foundry-Registry-Agent` enterprise application in Entra (a platform admin does this once; an unassigned project fails with `mi_not_authorized`, and a fresh assignment can take a few minutes to take effect), JFrog's Azure OIDC mapping grants read access to `byor-demo-docker`, GitHub's OIDC mapping grants this repository deploy access to `byor-demo-docker-local`, and a `byor-private` runner is registered for this repository.

The workflow creates the logical agent by default. Set the environment variable `IMPORT_EXISTING_AGENT=true` only if `mykp-hosted-agent` already exists in this Foundry project and the plan is intended to import it.

## Platform Contract Integration

### What is the Platform Contract?
This repository is an **application delivery repository**. It does not own or manage the private JFrog container registry connection or the top-level Microsoft Foundry account. All infrastructure dependencies and connection details are defined upstream in the platform foundation repository (`jfrog-oidc-foundry`) and published as a versioned **Platform Contract** (`foundry-<env>.json`).

The contract provides:
- **Registry connection**: `JFROG_REGISTRY_CONNECTION_NAME` (`jfrog-registry-acct`) and `JFROG_REGISTRY_CONNECTION_ID`.
- **JFrog endpoints**: `JF_URL` (`https://trialndswdc.jfrog.io`), `JFROG_REPO` (`byor-demo-docker`), and `JFROG_GITHUB_OIDC_PROVIDER` (`github-oidc`).
- **OIDC token exchange settings**: `REGISTRY_TOKEN_AUDIENCE`, `REGISTRY_TOKEN_ENDPOINT`, and `REGISTRY_OIDC_PROVIDER_NAME` (`oidc-byor`).
- **Foundry scope**: `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `FOUNDRY_ACCOUNT_NAME`.

### How the Contract is Used in Deployment
The deployment pipeline (`.github/workflows/deploy-agent.yml`) strictly consumes contract values from the protected GitHub Environment (`agent`):

1. **Build & Push Image (`build` job):**
   - Logs in to JFrog using GitHub Actions OIDC (`JFROG_GITHUB_OIDC_PROVIDER`) without passwords or static tokens.
   - Tags and pushes the container image to `<JF_URL host>/<JFROG_REPO>/agent-mykp:<tag>`.
   - Resolves the immutable `@sha256:...` digest.

2. **Validate Contract (`deploy` job):**
   - Validates that all required contract variables are present, endpoints are well-formed HTTPS URLs, and resource IDs match the target subscription.

3. **Deploy Hosted Agent (`infra/hosted-agent/main.tf`):**
   - Terraform provisions the data-plane agent (`azapi_data_plane_resource.hosted_agent`).
   - Sets `container_configuration.registry_connection_id = var.registry_connection_name` (`jfrog-registry-acct`).
   - At runtime, Foundry connects to JFrog using the account-level shared connection and exchanges its project managed identity token for an Artifactory read token to pull the image layers.

4. **Smoke Test:**
   - Calls the hosted agent endpoint (`FOUNDRY_PROJECT_ENDPOINT`) and verifies that the new version is active and answers requests.

### Ingesting Contract Updates
When `jfrog-oidc-foundry` publishes a new contract:
- **Using GitHub Copilot:** Run the prompt action `/apply-platform-contract` in chat.
- **Using the Import Script:**
  ```powershell
  # Download latest artifact if needed:
  gh run download --repo clekkas/jfrog-oidc-foundry -n platform-contract-dev -D .
  # Import values into the protected agent environment:
  ./scripts/import-platform-contract.ps1 -ContractPath foundry-dev.json -Repo clekkas/jfrog-agent-mykp -Environment agent
  ```
- **Using GitHub CLI directly:**
  ```bash
  jq -r '.values | to_entries[] | [.key, .value] | @tsv' foundry-dev.json | while IFS=$'\t' read -r k v; do
    gh variable set "$k" --repo clekkas/jfrog-agent-mykp --env agent --body "$v"
  done
  ```