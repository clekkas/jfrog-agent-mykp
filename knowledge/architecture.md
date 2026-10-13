<!-- scope: architecture, runner, runners, vnet, private endpoint, oidc, workflow, workflows, pipeline, state, tfstate, identity, identities, environment, environments, reviewers, digest, hosted agent, mykp, mykp-hosted-agent, jfrog-agent-mykp, jfrog-agent-byor, jfrog-oidc-foundry, platform repo, foundation repo, agent repo, concurrency, nsg, managed identity, mysecond-project-for-kp, kaiser-foundry-resource, agent-mykp, byor-demo-docker, byor-private -->
# Architecture and workflows (condensed overview)

Written 2026-10-12 from the repository contents and the live deployment. Where this differs from the generated asset inventory (`azure-assets.md`) the inventory is newer for live values such as version numbers. Subscription, tenant and application IDs are redacted on purpose.

## What the system is

This repository deploys the hosted agent `mykp-hosted-agent` into the Microsoft Foundry project `mysecond-project-for-kp`. The container image is stored in a private JFrog registry, not Azure Container Registry. Foundry authenticates to JFrog with OIDC token exchange, and GitHub authenticates to Azure and JFrog with OIDC. No client secrets are stored anywhere.

This repo is self-contained. It does not read any other repository's Terraform state and does not consume a platform contract file. All project values are embedded in `scripts/bootstrap-github-oidc.ps1`, which copies them into the `agent` GitHub environment as variables.

| Repository | Role |
|---|---|
| `jfrog-agent-mykp` (GitHub `clekkas/jfrog-agent-mykp`) | This repo: the app, image build, hosted-agent Terraform, smoke test, deploy identity and this knowledge base, for `mysecond-project-for-kp` |
| `jfrog-agent-byor` (GitHub `clekkas/byor-agent`) | The reference implementation for a different project, `workshop-demo-project`, in the same Foundry account. This repo was copied from it. |
| `jfrog-oidc-foundry` | The separate platform repo for the dev environment. It owns the account-shared registry connection and provisioned the runner VMs, VNet and state account that this repo reuses. It has no mykp environment and no workflow for this repo. |

## Current state

- The live agent is `mykp-hosted-agent`, active, using model `gpt-5-mini`. The latest version and image digest are in `azure-assets.md`.
- It runs in the project `mysecond-project-for-kp` of the Foundry account `kaiser-foundry-resource`.
- It pulls its image through the Foundry connection `jfrog-registry-acct`, an account-level shared connection that every project in the account can use. The project has no project-scoped connection of its own.
- Deploys come from the `agent` GitHub environment, restricted to the `main` branch. Required reviewers are not enabled because the GitHub plan does not support them on private repositories, so there is no human approval gate.

## Runner

- Jobs that touch Terraform state run on the self-hosted runner `byor-ci-mykp-runner-01`, label `byor-private`, registered only to this repo. It is a Standard_B2s_v2 Ubuntu VM in swedencentral in resource group `kaiser-foundry-rg`.
- Two other runner VMs share the same VNet `byor-ci-vnet`: `byor-ci-runner-01` (foundation repo) and `byor-ci-agent-runner-01` (the byor agent repo). The network security group rule `deny-vnet-inbound` blocks inbound traffic between them.
- Why a private VNet: the Terraform state account `tfstateb173d2d85c34` has public network access disabled. The only way in is the private endpoint `byor-ci-tfstate-blob-pe`, with the private DNS zone `privatelink.blob.core.windows.net`. A 403 on state from a laptop means you are outside the VNet.
- The VM has no public IP, no inbound access and no Azure identity of its own. Azure identity comes from the workflow: the `azure/login` action exchanges the job's GitHub OIDC token for an Entra token for the app `github-mykp-agent-deployer`.
- Because jobs on a shared VM can see leftovers of earlier jobs, the repository must stay private.
- The runner needs the Azure CLI. New VMs get it from cloud-init.

## Identities

| Identity | Used for | Access |
|---|---|---|
| `github-mykp-agent-deployer` (Entra app) | The `agent` environment: Terraform plan and apply | Foundry Project Manager on the project, Reader on the resource group, Storage Blob Data Contributor on the container `agent-tfstate-mykp` only |
| The project's managed identity | Foundry pulling the image from JFrog | Read-only mapping in JFrog, and an app role assignment on the Entra app `Foundry-Registry-Agent` |
| GitHub OIDC to JFrog | The build job pushing the image | JFrog `github-oidc` identity mapping for this repo and the main branch |

The federated credential is bound to the GitHub environment `agent`, not to a branch. The subject has the form `repo:<owner>/<repo>:environment:agent`, using GitHub's ID-based subject format.

The Entra app `Foundry-Registry-Agent` is the token audience for the JFrog exchange and requires assignment. Every project identity that pulls images must be assigned to it. Without it, creating a version fails with `mi_not_authorized`. The identity of `mysecond-project-for-kp` was assigned on 2026-10-13 UTC, and Entra took a few minutes to honour it.

## Workflows

Both workflows are GitHub Actions files in `.github/workflows` and share the concurrency group `hosted-agent-deployment`, so they queue instead of overlapping.

| Workflow | Trigger | What it does |
|---|---|---|
| `deploy-agent.yml` (Build and deploy hosted agent) | Push to `main` touching `app.py`, `knowledge/**`, `requirements*.txt`, `Dockerfile`, `infra/hosted-agent/**`, `scripts/test-hosted-agent.py` or the workflow; or manual dispatch with an optional `image_tag` | The build job runs on `ubuntu-latest`: JFrog login with GitHub OIDC, docker build for linux/amd64, container smoke test, push, resolve the immutable digest. A manual run with `image_tag` skips build and push and deploys that existing tag. The deploy job runs on the self-hosted runner: Azure login, validate the settings against the live connection, Terraform init, plan and apply with no pause, then wait for the version to become active and smoke test it. |
| `agent-plan.yml` (Plan hosted agent, no apply) | Manual only, optional `image_uri` | Runs `terraform plan` for `infra/hosted-agent` and never applies. Without `image_uri` it plans with the live agent's current image, so it needs an existing agent. |

## Design points

- Private state: every Terraform run happens on a `byor-private` runner inside the VNet.
- Environment-scoped OIDC: the federated credential is bound to the `agent` environment, which only deploys from `main`.
- Digest-only deploys: Terraform receives only an `@sha256:` reference under `byor-demo-docker/agent-mykp`. The workflow also re-checks the live connection target, type (`registry_connection`) and mode (`oauth_token_exchange`) before Terraform runs.
- State: container `agent-tfstate-mykp`, key `hosted-agent/mykp.tfstate`, in the account `tfstateb173d2d85c34`.
- The agent is a Foundry data-plane resource managed with AzAPI, with `prevent_destroy`.

## Risks and open items

- No reviewer gate: a push to `main` that touches a deploy path (including `knowledge/**`) builds and deploys a new version with no human approval.
- No pause between plan and apply in `deploy-agent.yml`; run `agent-plan.yml` first for anything risky.
- JFrog refuses to overwrite an existing tag. The tag is `sha-<first 7 chars of the commit>`, so running the full workflow a second time on the same commit fails at push. Use the `image_tag` input to redeploy, or make a new commit.
- The SKU allow-list exists twice, hardcoded in `infra/hosted-agent/main.tf` and in the variable `SUPPORTED_AGENT_SKUS`, and can drift apart.
- Three runner VMs share one VNet, one state account and one private endpoint with the other repos. Container-scoped RBAC keeps this repo's state separate.
- Foundation and byor-agent repos still own their own runners; stopping their VMs does not affect this repo, but the runner here must be online for any deploy.
