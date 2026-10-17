# jfrog-agent-mykp — JFrog BYOR hosted agent for mykp 🔁

**A second Microsoft Foundry hosted agent, same OIDC-token-exchange pull pattern as [`byor-agent`](https://github.com/clekkas/byor-agent), deployed to an independent Foundry project (`mysecond-project-for-kp`) with its own identity, state, and CI runner.**

[![Deploy](https://github.com/clekkas/jfrog-agent-mykp/actions/workflows/deploy-agent.yml/badge.svg)](https://github.com/clekkas/jfrog-agent-mykp/actions/workflows/deploy-agent.yml)

This repository deploys the `mykp-hosted-agent` hosted agent to the Foundry project `mysecond-project-for-kp`, using the same FastAPI Responses container and Terraform/AzAPI deployment pattern as `byor-agent`, with a separate GitHub repository, deployment identity, and Terraform state container.

## 🎯 What This Repo Provides

- Proof that the BYOR pattern **isolates cleanly across projects** — two independently bootstrapped agent repos sharing one foundation's registry connection and runner infrastructure, with no cross-repo state access
- The same FastAPI **Responses-protocol** container and Terraform/AzAPI hosted-agent management as `byor-agent`, targeting a distinct project (`mysecond-project-for-kp`) and image path (`agent-mykp`) to avoid tag collisions
- A **guarded platform-contract importer** that validates target/integrity before writing any variable — never a bulk `gh variable set` copy

## 🗺️ Project

| Setting | Value |
|---|---|
| Tenant | `16b3c013-d300-468d-ac64-7eda0820b6d3` |
| Foundry account | `kaiser-foundry-resource` |
| Project ID | `/subscriptions/0e494a0c-e2e6-41f8-8a50-6064d842225e/resourceGroups/kaiser-foundry-rg/providers/Microsoft.CognitiveServices/accounts/kaiser-foundry-resource/projects/mysecond-project-for-kp` |
| Project endpoint | `https://kaiser-foundry-resource.services.ai.azure.com/api/projects/mysecond-project-for-kp` |
| Model deployment | `gpt-5-mini` |

This application repository is independently bootstrapped, but depends on infrastructure owned by [`jfrog-oidc-foundry`](https://github.com/clekkas/jfrog-oidc-foundry): the account-shared Foundry connection `jfrog-registry-acct`, the Terraform state account `tfstateb173d2d85c34`, and the runner infrastructure. It has its own state container and repo-scoped runner. `scripts/bootstrap-github-oidc.ps1` initializes this project's deployment variables without reading foundation state or downloading a contract.

## 🚀 Quick Start

Install dependencies and run the container:

```powershell
python -m pip install -r requirements.txt
python -m uvicorn app:app --host 127.0.0.1 --port 8088
```

In another terminal, run the local Responses and health checks:

```powershell
python test_local.py
```

Offline regression tests (no Azure, JFrog, or GitHub writes):

```powershell
python -m unittest discover -s tests -q
pwsh -NoProfile -File scripts/test-import-platform-contract.ps1
```

> 💡 **Tip**: The importer harness uses Python's standard library as an independent checksum oracle and mocks every `gh` call. `test-local.ps1` and `test-local.sh` delegate to `test_local.py`, honor `BASE`, and propagate the same execution-provenance checks. They require Python (`python` on PowerShell, `python3` on Bash).

## 🔁 CI/CD

`.github/workflows/deploy-agent.yml` follows the reference pipeline: build and smoke-test a `linux/amd64` image, push it to JFrog with GitHub OIDC, resolve its immutable digest, then deploy with Terraform from the self-hosted `byor-private` runner. This repo uses image name `agent-mykp` in the shared `byor-demo-docker` repository to avoid tag collisions with the reference repo. `agent-plan.yml` is manual and never applies.

The workflow uses the protected GitHub Environment `agent` in this repository. Bootstrap it with `./scripts/bootstrap-github-oidc.ps1 -Repo clekkas/jfrog-agent-mykp -NoRequiredReviewers` (separate state container `agent-tfstate-mykp`, key `hosted-agent/mykp.tfstate`). Backend config, Terraform plans, and state must not be committed.

Before deployment, confirm this Foundry project's managed identity is assigned to the `Foundry-Registry-Agent` enterprise application in Entra (a platform admin does this once; an unassigned project fails with `mi_not_authorized`, and a fresh assignment can take a few minutes to take effect), JFrog's Azure OIDC mapping grants read access to `byor-demo-docker`, GitHub's OIDC mapping grants this repository deploy access to `byor-demo-docker-local`, and a `byor-private` runner is registered for this repository.

The workflow creates the logical agent by default. Set the environment variable `IMPORT_EXISTING_AGENT=true` only if `mykp-hosted-agent` already exists in this Foundry project and the plan is intended to import it.

Set the protected environment variable `MODEL_DEPLOYMENT_NAME` to the desired deployment for model mode, or an empty value for intentional echo mode. Terraform passes this setting to the container; `azure.yaml` is not the release source of truth.

## 📜 Platform Contract Integration

### ❓ What Is the Platform Contract?
This repository is an **application delivery repository**. It does not manage registry connections or the Foundry account. The foundation publishes versioned **Platform Contracts** (`foundry-<env>.json`) for projects it manages. This repo can optionally import approved updates, but only from a contract matching its already initialized project.

**The current foundation dev contract targets `workshop-demo-project`, not `mysecond-project-for-kp`. It must not be imported here. The foundation does not currently publish a matching mykp contract.** Keep using the existing bootstrap configuration until the platform owner provides an approved published contract for this project. Do not edit a workshop artifact and recompute its checksum.

The contract provides:
- **Registry connection**: `JFROG_REGISTRY_CONNECTION_NAME` (`jfrog-registry-acct`) and `JFROG_REGISTRY_CONNECTION_ID`.
- **JFrog endpoints**: `JF_URL` (`https://trialndswdc.jfrog.io`), `JFROG_REPO` (`byor-demo-docker`), and `JFROG_GITHUB_OIDC_PROVIDER` (`github-oidc`).
- **OIDC token exchange settings**: `REGISTRY_TOKEN_AUDIENCE`, `REGISTRY_TOKEN_ENDPOINT`, and `REGISTRY_OIDC_PROVIDER_NAME` (`oidc-byor`).
- **Foundry scope**: `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `FOUNDRY_ACCOUNT_NAME`.

### 🔄 How the Contract Is Used in Deployment
The deployment pipeline (`.github/workflows/deploy-agent.yml`) consumes deployment variables from the protected GitHub Environment (`agent`), initialized by bootstrap or refreshed through a validated matching-project contract:

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
   - Verifies the exact candidate version is active with the intended immutable image and model setting.
   - Creates a session pinned to that version, invokes with its `agent_session_id`, and deletes only that test session afterward. Public endpoint routing is unchanged.
   - Uses an in-scope prompt and requires `metadata.execution_mode` to match the configuration. Model mode additionally requires `model_deployment` and a nonempty `upstream_response_id` recorded after a successful model call. Scope-blocked, deterministic lookup, and echo responses cannot pass as model responses.

### 📥 Ingesting Contract Updates
After bootstrap, obtain an approved published contract for **this exact project**, inspect its source run, and use the guarded importer (or `/apply-platform-contract`):

```powershell
# Example filename only; this matching artifact must first be supplied by the platform owner.
./scripts/import-platform-contract.ps1 -ContractPath foundry-mykp.json -Repo clekkas/jfrog-agent-mykp -Environment agent
```

The importer requires contract version 1, a complete flat string map, and a checksum matching the publisher's canonical UTF-8 JSON plus trailing LF. It compares tenant, subscription, resource group, account, project, resource ID, and endpoint against the existing `agent` environment before any writes. App-owned identity/state settings are rejected. Missing target settings require bootstrap first; mismatches require a matching contract, not a retargeting override. A checksum checks integrity, not provenance: approve the source artifact before importing.

Do not bulk-copy variables with `gh variable set` loops: that bypasses target and integrity checks. An import updates variables only; it does not trigger a deployment.

For manual deployed-agent validation, acquire a token for `https://ai.azure.com` into `AZURE_AI_ACCESS_TOKEN` and run:

```powershell
python scripts/test-hosted-agent.py `
  --endpoint "https://kaiser-foundry-resource.services.ai.azure.com/api/projects/mysecond-project-for-kp" `
  --agent mykp-hosted-agent --version "<candidate-version>" `
  --expected-image "<registry/repository/agent-mykp@sha256:digest>" `
  --expected-model gpt-5-mini
```

Pass `--expected-model ""` for intentional echo mode; omit the option to infer the deployment from the verified candidate definition. Old images without execution metadata fail these stronger checks and need to be rebuilt.

## 🛠️ Commands Reference

| Command | Description |
|---|---|
| `python test_local.py` | Local Responses + health checks against a running container |
| `python -m unittest discover -s tests -q` | Offline regression tests (no Azure/JFrog/GitHub writes) |
| `pwsh -NoProfile -File scripts/test-import-platform-contract.ps1` | Offline harness for the contract importer's checksum/target validation |
| `./scripts/bootstrap-github-oidc.ps1 -Repo clekkas/jfrog-agent-mykp -NoRequiredReviewers` | One-time: agent identity, RBAC, `agent-tfstate-mykp` container, protected GitHub Environment |
| `./scripts/import-platform-contract.ps1 -ContractPath <file> -Repo clekkas/jfrog-agent-mykp -Environment agent` | Guarded import of an approved, matching-project platform contract |
| `python scripts/test-hosted-agent.py --endpoint <url> --agent mykp-hosted-agent --version <n> --expected-image <digest> --expected-model gpt-5-mini` | Verify a specific candidate version is active with the expected image/model |

## 📚 Related Repositories

| Repo | Role |
|---|---|
| [`jfrog-oidc-foundry`](https://github.com/clekkas/jfrog-oidc-foundry) | Foundation — owns the shared registry connection, runners, and state this repo depends on |
| [`byor-agent`](https://github.com/clekkas/byor-agent) | Sibling app repo — same pattern, the primary/reference Foundry project |
| [`byor-agent-dockerhub`](https://github.com/clekkas/byor-agent-dockerhub) | Anonymous-pull proof — public Docker Hub, no registry connection, no OIDC |
| [`byor-agent-docker`](https://github.com/clekkas/byor-agent-docker) | Anonymous-pull proof — self-hosted registry, no registry connection, no OIDC |

## ⚠️ Important Notes

- The current foundation dev contract targets `workshop-demo-project`, **not** `mysecond-project-for-kp` — it must not be imported here. Keep using the existing bootstrap configuration until the platform owner provides an approved contract for this project.
- Before deployment, confirm this Foundry project's managed identity is assigned to the `Foundry-Registry-Agent` enterprise application in Entra (a platform admin does this once; an unassigned project fails with `mi_not_authorized`).
- Set `IMPORT_EXISTING_AGENT=true` only if `mykp-hosted-agent` already exists in this Foundry project and the plan is intended to import it.

## 🤝 Contributing

This is an application repo for a specific workshop engagement. Issues and suggestions are welcome, but expect the scope to stay narrow by design.

## 📄 License

Internal proof-of-concept — no license file; not intended for redistribution outside this engagement.