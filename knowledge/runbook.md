<!-- scope: runbook, bootstrap, state, tfstate, import, deploy, deployment, rollback, plan, apply, rbac, role, roles, permission, permissions, reviewers, checklist, troubleshoot, troubleshooting, sku, skus, smoke test, digest, terraform, runner, runners, queued, offline, 403, 422, environment, federated credential, image_tag, mykp, mykp-hosted-agent, agent-tfstate-mykp, mykp.tfstate, mi_not_authorized, workflow_dispatch, image_uri, import_existing_agent, jfrog-agent-mykp -->
# Runbook (condensed): how to operate this agent repo

Written 2026-10-12 from this repository's scripts, workflows and the first live deployment. IDs are redacted. Use it for the procedure and the reasoning; for current values see the architecture document and the asset inventory.

## Standing safety rules

- Do not run Terraform apply until the plan has been reviewed. There is no approval gate in the workflow, so use `agent-plan.yml` first for anything risky.
- If a plan wants to destroy or replace the agent, stop. It means wrong state, wrong variables or drift. `prevent_destroy` also blocks it.
- If a plan wants to create `mykp-hosted-agent` while it already exists in the Foundry project, the state is missing it: set `IMPORT_EXISTING_AGENT=true`, deploy once, then set it back to `false`.
- Never commit state files, plan files, `backend.hcl` or tfvars containing secrets. Never make the repository public.
- This repo manages only the hosted agent. It must not create or change the Foundry registry connection and must not read any other repo's Terraform state.

## Ownership

This repo owns the image build, the JFrog push, the hosted-agent Terraform, the smoke test, its deploy identity `github-mykp-agent-deployer`, its GitHub environment `agent` and its runner registration. It reuses the account-shared Foundry connection `jfrog-registry-acct`, the state account `tfstateb173d2d85c34` (with its own container) and the VNet. Nothing needs to be downloaded from another repository.

## Project values

All values live in `scripts/bootstrap-github-oidc.ps1` and are written as variables on the `agent` GitHub environment. They are identifiers and endpoints, never secrets.

| Variable | Meaning |
|---|---|
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP` | Where the Foundry project lives |
| `FOUNDRY_ACCOUNT_NAME`, `FOUNDRY_PROJECT_NAME`, `FOUNDRY_PROJECT_RESOURCE_ID`, `FOUNDRY_PROJECT_ENDPOINT` | The project the agent is released into (`mysecond-project-for-kp`) |
| `JFROG_REGISTRY_CONNECTION_NAME` | The connection hosted agents reference: `jfrog-registry-acct` |
| `JF_URL`, `JFROG_REPO` | JFrog base URL and the Docker repository key (`byor-demo-docker`) |
| `JFROG_GITHUB_OIDC_PROVIDER` | JFrog OIDC provider for GitHub pushes: `github-oidc` |
| `REGISTRY_TOKEN_AUDIENCE`, `REGISTRY_TOKEN_ENDPOINT`, `REGISTRY_OIDC_PROVIDER_NAME` | Entra-to-JFrog token exchange settings, kept for the inventory |
| `AGENT_AZURE_CLIENT_ID` | Client ID of the deploy identity |
| `AGENT_STATE_RESOURCE_GROUP`, `AGENT_STATE_STORAGE_ACCOUNT`, `AGENT_STATE_CONTAINER`, `AGENT_STATE_KEY` | Where the Terraform state lives |
| `MODEL_DEPLOYMENT_NAME`, `SUPPORTED_AGENT_SKUS`, `IMPORT_EXISTING_AGENT` | Agent settings |

`RUNNER_LABEL` (`byor-private`) and `TERRAFORM_VERSION` are repository variables because `runs-on` is evaluated before the environment is entered. To change the target project, edit the values in the bootstrap script and re-run it.

## State layout

One storage account, `tfstateb173d2d85c34`, public access disabled, reachable only through the private endpoint from the runner VNet. This repo's state is in container `agent-tfstate-mykp`, key `hosted-agent/mykp.tfstate`. The blob data role is granted at container scope only. The bootstrap script lists any blob data role the deploy identity holds outside its own container and fails if it finds one.

## RBAC summary

| Principal | Role | Scope |
|---|---|---|
| Deploy identity `github-mykp-agent-deployer` | Foundry Project Manager | The Foundry project |
| Deploy identity | Reader | Resource group `kaiser-foundry-rg` |
| Deploy identity | Storage Blob Data Contributor | Container `agent-tfstate-mykp` only |
| The operator running bootstrap | Storage Blob Data Contributor | Container `agent-tfstate-mykp` |

Caution: the built-in Foundry Project Manager role can also write project connections, so the deployer could in principle alter project connections. Review plans that touch anything other than the agent.

## OIDC and environments

The deploy identity has one federated credential bound to the GitHub environment `agent`, not a branch: subject `repo:<owner>/<repo>:environment:agent` (ID-based form). The environment is restricted to the `main` branch. It holds the variables above. Required reviewers are off because the GitHub plan returns HTTP 422 for required reviewers on private repositories; the bootstrap script is run with `-NoRequiredReviewers`. Re-run it with `-Reviewers <user-or-org/team>` once the plan supports them.

## Setup (already done for this deployment)

1. Confirm the project lists the shared connection: GET `<project resource id>/connections/jfrog-registry-acct?api-version=2025-06-01` should return target `https://trialndswdc.jfrog.io`, type `registry_connection`, mode `oauth_token_exchange`.
2. Run `./scripts/bootstrap-github-oidc.ps1 -Repo clekkas/jfrog-agent-mykp -NoRequiredReviewers`. It refuses a public repository, creates the Entra app with its federated credential, the state container with container-scoped RBAC, the `agent` environment with the `main` branch policy, all variables, and an ignored `infra/hosted-agent/backend.hcl`.
3. JFrog (administrator): add a `github-oidc` identity mapping for this repo (claims `{"ref": "refs/heads/main", "repository": "clekkas/jfrog-agent-mykp"}`) with read and deploy permission on `byor-demo-docker-local`, and an `oidc-byor` mapping for the project's managed identity with read access to `byor-demo-docker`.
4. Entra: assign the project's managed identity to the app `Foundry-Registry-Agent` (default access role).
5. Register a `byor-private` runner for this repository. The VM `byor-ci-mykp-runner-01` is the one in use.
6. Run `deploy-agent.yml` (manual dispatch or a push to `main`).

## Deploying the agent

- CI path: push to `main` touching a deploy path, or run `deploy-agent.yml` manually. For anything risky run `agent-plan.yml` first; it never applies. Both are serialized by the concurrency group.
- The image tag is `sha-<7-char commit>`; Terraform only receives the immutable `@sha256:` digest. Preflight fails the run before Terraform if the variables, project endpoint, connection (target, type, mode), digest repository or requested SKU are wrong.
- JFrog will not overwrite an existing tag. To redeploy an image that is already pushed, run `deploy-agent.yml` manually with `image_tag` set, for example `sha-d0a6b88`. This skips build and push.
- Manual path: `deploy.ps1` or `deploy.sh` with a digest-pinned image, from a machine that can reach the private state endpoint (normally only the runner can).
- Validation: the smoke test script waits for the exact Terraform output version to become active, checks its image matches, and invokes the Responses endpoint. A successful apply alone is not readiness.

## Troubleshooting

- Deploy job stays queued: the `byor-private` runner for this repo is offline; start the VM `byor-ci-mykp-runner-01` and check the runner service.
- `Unable to locate executable file: az` in a login step: the runner VM lacks the Azure CLI; install it on the VM.
- 403 on state: you are outside the VNet, or the identity lacks the container role.
- HTTP 422 creating an environment with reviewers: the GitHub plan does not support required reviewers on private repositories; use `-NoRequiredReviewers`.
- Workflow dispatch returns 422: the workflow is disabled; re-enable it.
- JFrog login step fails with `failed to exchange OIDC token: 403 Forbidden`: the JFrog GitHub mapping for this repo is missing, or its claims JSON is invalid. It must be a single JSON object.
- Push fails with `unauthorized: No permission to overwrite manifest`: the tag already exists. Deploy it with `image_tag`, or commit a change to get a new tag.
- Apply fails with `mi_not_authorized`: the project's managed identity is not assigned to `Foundry-Registry-Agent`. Assign it and retry; allow a few minutes for Entra.
- Apply fails with `Resource already exists`: an earlier apply created the agent but did not save it in state. Set `IMPORT_EXISTING_AGENT=true`, deploy once, then set it back to `false`.
- Image pulls but the version never becomes active: wrong CPU architecture. Build `linux/amd64` explicitly.
- Terraform state lock error: another run is active or crashed; wait for the concurrency group or break the lock after confirming nothing is running.

## Knowledge base maintenance

The files in `knowledge/` are copied into the image and sent to the model with every request (about 60 KB in total at most; larger files are left out and reported by `/healthz`). `azure-assets.md` is generated by `scripts/generate-asset-inventory.ps1` from live Azure and GitHub data; do not edit it by hand, re-run the script. Other files are hand-written. A file may declare extra scope words with a scope comment on its first line. Pushing a change under `knowledge/**` redeploys the agent automatically, with no approval gate.
