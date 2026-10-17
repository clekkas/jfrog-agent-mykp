# Asset inventory: Foundry hosted agent `mykp-hosted-agent` (JFrog + OIDC)

Generated 2026-10-13 04:04 UTC by `scripts/generate-asset-inventory.ps1` from live Azure, GitHub and Terraform data.
IDs (subscription, tenant, object and client IDs) are redacted. Secrets are never collected.

## Summary

- **Project**: a Microsoft Foundry hosted agent (`mykp-hosted-agent`) whose container image is stored in **JFrog Artifactory**, not Azure Container Registry ("bring your own registry").
- **Image pull**: Foundry pulls the image using **OIDC token exchange**. The Foundry project's managed identity exchanges an Entra token for a short-lived JFrog token, so no registry password is stored.
- **Model**: the agent answers with model **`gpt-5-mini`** through the Foundry project endpoint, using its own platform-managed identity.
- **CI/CD**: GitHub Actions builds the image, pushes it to JFrog (GitHub OIDC), and applies Terraform for the hosted agent only. The agent is managed through the Foundry data plane with AzAPI. All authentication uses OIDC; no secrets are stored.
- **Platform**: this repo is self-contained. It uses the account-shared registry connection `jfrog-registry-acct` (owned by the dev foundation environment), the shared Terraform state account and VNet, and its own repo-scoped runner.
- **Azure location**: resource group `<foundry-resource-group>`, Foundry in **eastus**.

## Foundry

- **Account**: `<foundry-account>` (eastus), pre-existing
- **Project**: `mysecond-project-for-kp`, endpoint `https://<foundry-account>.services.ai.azure.com/api/projects/mysecond-project-for-kp`, identity type: SystemAssigned

### Model deployments

| Deployment | Model | Version | SKU |
|---|---|---|---|
| `gpt-5-mini` | gpt-5-mini | 2025-08-07 | GlobalStandard |
| `text-embedding-3-small` | text-embedding-3-small | 1 | Standard |
| `gpt-5.4-mini` | gpt-5.4-mini | 2026-03-17 | GlobalStandard |

### Project connections

| Connection | Category | Target | Metadata |
|---|---|---|---|
| `jfrog-registry-acct` | CustomKeys | https://trialndswdc.jfrog.io | mode=oauth_token_exchange, type=registry_connection |

The `jfrog-registry-acct` connection is an account-level shared connection (visible to every project in the account). It stores the OIDC token-exchange settings: Entra app audience, token endpoint `/access/api/v1/oidc/token`, and JFrog provider name `oidc-byor`. This repo references it by name and does not manage it.

### Hosted agent `mykp-hosted-agent`

- **Latest version**: 3 (active), protocol: responses 2.0.0
- **Image**: `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp@sha256:cef6a46aa198d8186f00940dbf992816fdda110c5ed012b57b716fd17ff7b104` via registry connection `jfrog-registry-acct`
- **Agent identity**: platform-managed (blueprint `mykp-hosted-agent-2a145`); it can call project models by default.

| Version | Status | Created | Image | Resources | Env |
|---|---|---|---|---|---|
| 3 | active | 2026-10-13 03:51 UTC | `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp@sha256:cef6a46aa198d8186f00940dbf992816fdda110c5ed012b57b716fd17ff7b104` | 0.5 CPU / 1Gi | AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5-mini |
| 2 | active | 2026-10-13 03:49 UTC | `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp@sha256:cef6a46aa198d8186f00940dbf992816fdda110c5ed012b57b716fd17ff7b104` | 0.5 CPU / 1Gi | AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5-mini |
| 1 | active | 2026-10-13 03:45 UTC | `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp@sha256:cef6a46aa198d8186f00940dbf992816fdda110c5ed012b57b716fd17ff7b104` | 0.5 CPU / 1Gi | AZURE_AI_MODEL_DEPLOYMENT_NAME=gpt-5-mini |

## Azure resources in `<foundry-resource-group>`

| Name | Type | Region | Origin |
|---|---|---|---|
| `<foundry-account>` | Microsoft.CognitiveServices/accounts | eastus | Platform: Foundry |
| `workshop-demo-project-v-resource` | Microsoft.CognitiveServices/accounts | eastus2 | Platform: Foundry |
| `<foundry-account>/mysecond-project-for-kp` | Microsoft.CognitiveServices/accounts/projects | eastus | Platform: Foundry |
| `<foundry-account>/workshop-demo-project` | Microsoft.CognitiveServices/accounts/projects | eastus | Platform: Foundry |
| `workshop-demo-project-v-resource/workshop-demo-project-v2` | Microsoft.CognitiveServices/accounts/projects | eastus2 | Platform: Foundry |
| `byor-ci-agent-runner-01_OsDisk_1_da31917457fe4344891f25bf6eb4ba47` | Microsoft.Compute/disks | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-mykp-runner-01_OsDisk_1_04b7c42682e549ae8d5ee9ce3c2fb82e` | Microsoft.Compute/disks | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-runner-01_OsDisk_1_ffb7fab3b34e4d11a67e920b1139afb9` | Microsoft.Compute/disks | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-agent-runner-key` | Microsoft.Compute/sshPublicKeys | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-mykp-runner-key` | Microsoft.Compute/sshPublicKeys | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-runner-key` | Microsoft.Compute/sshPublicKeys | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-agent-runner-01` | Microsoft.Compute/virtualMachines | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-mykp-runner-01` | Microsoft.Compute/virtualMachines | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-runner-01` | Microsoft.Compute/virtualMachines | swedencentral | Platform: CI runner (foundation repo) |
| `tfstateb173d2d85c34-<redacted>` | Microsoft.EventGrid/systemTopics | eastus | Other |
| `workshop-demo-project-v-resource-appinsights` | Microsoft.Insights/components | eastus2 | Other |
| `byor-ci-agent-runner-nic` | Microsoft.Network/networkInterfaces | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-mykp-runner-nic` | Microsoft.Network/networkInterfaces | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-runner-nic` | Microsoft.Network/networkInterfaces | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-tfstate-blob-pe.nic.<redacted>` | Microsoft.Network/networkInterfaces | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-runner-nsg` | Microsoft.Network/networkSecurityGroups | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-vnet-private-endpoints-nsg-swedencentral` | Microsoft.Network/networkSecurityGroups | swedencentral | Platform: CI runner (foundation repo) |
| `privatelink.blob.core.windows.net` | Microsoft.Network/privateDnsZones | global | Platform: CI runner (foundation repo) |
| `privatelink.blob.core.windows.net/byor-ci-vnet-link` | Microsoft.Network/privateDnsZones/virtualNetworkLinks | global | Platform: CI runner (foundation repo) |
| `byor-ci-tfstate-blob-pe` | Microsoft.Network/privateEndpoints | swedencentral | Platform: CI runner (foundation repo) |
| `byor-ci-vnet` | Microsoft.Network/virtualNetworks | swedencentral | Platform: CI runner (foundation repo) |
| `workshop-demo-project-v-resource-logs` | Microsoft.OperationalInsights/workspaces | eastus2 | Other |
| `tfstateb173d2d85c34` | Microsoft.Storage/storageAccounts | eastus | Platform: Terraform state (foundation repo) |

### Terraform state

- **Hosted agent** (`infra/hosted-agent`): remote state in storage account `tfstateb173d2d85c34`, its own container `agent-tfstate-mykp`, key `hosted-agent/mykp.tfstate`. Entra auth only. Public network access is **disabled by subscription policy**, so state is reachable only through the private endpoint from the platform-owned runner VNet. It imports the existing logical agent, preserves Foundry version history, and prevents destroy.
- **Foundation state** (dev registry connection, other runners): owned by the foundation repo, in a different container. This project's deploy identity has no access to it.

## Microsoft Entra ID

| App | Purpose | Origin | Token version |
|---|---|---|---|
| `Foundry-Registry-Agent` | Token audience for the JFrog OIDC exchange (Foundry pulls images) | Pre-existing | v2 |
| `github-mykp-agent-deployer` | GitHub Actions agent deploy identity (federated to environment agent, no secret) | Created: bootstrap script | v2 |

### Federated credentials

| App | Credential | Subject | Issuer |
|---|---|---|---|
| `github-mykp-agent-deployer` | `github-clekkas-jfrog-agent-mykp-agent-ids` | `repo:clekkas@<id>/jfrog-agent-mykp@<id>:environment:agent` | https://token.actions.githubusercontent.com |

The repo uses GitHub's ID-based ("immutable") OIDC subjects, so the credential containing `@` IDs is the one in use.

### Role assignments

| Principal | Role | Scope |
|---|---|---|
| GitHub Actions agent deploy identity | Foundry Project Manager | accounts `<foundry-account>` / projects `mysecond-project-for-kp` |
| GitHub Actions agent deploy identity | Reader | resource group `<foundry-resource-group>` |
| GitHub Actions agent deploy identity | Storage Blob Data Contributor | storageAccounts `tfstateb173d2d85c34` / blobServices `default` / containers `agent-tfstate-mykp` |
| Operator (user) | Storage Blob Data Contributor | storageAccounts `tfstateb173d2d85c34` |

## JFrog Artifactory

- **Instance**: `https://trialndswdc.jfrog.io`
- **Repositories**: `byor-demo-docker` (virtual; image path `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp`) and `byor-demo-docker-local` (local; where pushes land)
- **Image tags**: CI pushes `agent-mykp:sha-<commit>`. JFrog refuses to overwrite an existing tag.
- **OIDC integrations**:

| Integration | Used by | Trusts | Access |
|---|---|---|---|
| `oidc-byor` | Foundry (image pull) | Entra tenant (Azure provider), audience = the token-audience Entra app; identity mapping on the project managed identity (`oid`) | Read-only on `byor-demo-docker` |
| `github-oidc` | GitHub Actions build job (image push) | `https://token.actions.githubusercontent.com`, organization `clekkas`; mapping `repository=clekkas/jfrog-agent-mykp`, `ref=refs/heads/main` | Read + Deploy on `byor-demo-docker-local` |

## GitHub (`clekkas/jfrog-agent-mykp`)

- **Workflow**: `.github/workflows/deploy-agent.yml`. `build` runs on ubuntu-latest; `deploy` runs on the self-hosted runner. It triggers on pushes to `main` and on manual dispatch, with optional `image_tag`.
- **Last run**: "Build and deploy hosted agent": completed/success at commit `d0a6b88`

### Self-hosted runners

| Runner | Status | Labels |
|---|---|---|
| `byor-ci-mykp-runner-01` | online | self-hosted, Linux, X64, byor-private |

### Agent environment variables

`AGENT_AZURE_CLIENT_ID`, `AGENT_STATE_CONTAINER`, `AGENT_STATE_KEY`, `AGENT_STATE_RESOURCE_GROUP`, `AGENT_STATE_STORAGE_ACCOUNT`, `AZURE_RESOURCE_GROUP`, `AZURE_SUBSCRIPTION_ID`, `AZURE_TENANT_ID`, `FOUNDRY_ACCOUNT_NAME`, `FOUNDRY_PROJECT_ENDPOINT`, `FOUNDRY_PROJECT_NAME`, `FOUNDRY_PROJECT_RESOURCE_ID`, `IMPORT_EXISTING_AGENT`, `JF_URL`, `JFROG_GITHUB_OIDC_PROVIDER`, `JFROG_REGISTRY_CONNECTION_ID`, `JFROG_REGISTRY_CONNECTION_NAME`, `JFROG_REPO`, `MODEL_DEPLOYMENT_NAME`, `REGISTRY_OIDC_PROVIDER_NAME`, `REGISTRY_TOKEN_AUDIENCE`, `REGISTRY_TOKEN_ENDPOINT`, `SUPPORTED_AGENT_SKUS`

## Repository layout

| Path | Purpose |
|---|---|
| `app.py` | FastAPI Responses-protocol agent (echo or model mode); serves `/responses`, `/readiness`, `/liveness` |
| `azure.yaml` | Legacy azd compatibility/reference definition; not the CI/CD source of truth |
| `infra/hosted-agent/` | Terraform (AzAPI data plane) for the logical hosted agent and versions |
| `scripts/bootstrap-github-oidc.ps1` | Agent Entra app, environment-scoped federated credential, agent-state RBAC, `agent` GitHub Environment |
| `scripts/generate-asset-inventory.ps1` | Generates this file |
| `knowledge/` | Knowledge files bundled into the agent image |

## Capital Cities
Greece = Athina
Thailand = Kuntep
