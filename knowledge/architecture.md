<!-- scope: mykp, mysecond-project-for-kp, kaiser-foundry-resource, jfrog-agent-mykp, jfrog-agent-byor, jfrog-oidc-foundry, agent-mykp, byor-demo-docker, hosted agent, mykp-hosted-agent, terraform state, byor-private -->
# Architecture

Updated 2026-10-12. This document describes the target deployment. This repo is self-contained and defines all values for the target project.

## Repository ownership

| Repository | Responsibility |
|---|---|
| `jfrog-oidc-foundry` | Separate platform repo for other environments; not used by this deployment |
| `jfrog-agent-byor` | Reference hosted-agent implementation for a different project on the same Foundry account |
| `jfrog-agent-mykp` | Hosted-agent application, image build, Terraform release, and smoke tests for `mysecond-project-for-kp` |

This repository does not manage the registry connection: it uses the account-shared connection `jfrog-registry-acct`.

## Target Foundry project

- Tenant: `16b3c013-d300-468d-ac64-7eda0820b6d3`
- Subscription: `0e494a0c-e2e6-41f8-8a50-6064d842225e`
- Resource group: `kaiser-foundry-rg`
- Foundry account: `kaiser-foundry-resource`
- Project: `mysecond-project-for-kp`
- Project resource ID: `/subscriptions/0e494a0c-e2e6-41f8-8a50-6064d842225e/resourceGroups/kaiser-foundry-rg/providers/Microsoft.CognitiveServices/accounts/kaiser-foundry-resource/projects/mysecond-project-for-kp`
- Project endpoint: `https://kaiser-foundry-resource.services.ai.azure.com/api/projects/mysecond-project-for-kp`
- Model deployment: `gpt-5-mini`

The hosted agent is `mykp-hosted-agent`, implemented as a FastAPI Responses 2.0.0 container. Its project managed identity is distinct from the identity in `workshop-demo-project`; get its principal ID (`6dbf0c22-f50c-4a01-98d9-2a14218abb2f`) from the project, never from the reference repo.

## Image and release

GitHub Actions publishes `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp:<tag>` and resolves the immutable digest before Terraform deploys it. The reference repo uses image name `agent` in the same JFrog repository. GitHub OIDC pushes images; the Foundry project identity uses the platform-owned registry connection and JFrog OIDC mapping to pull them.

## State and workflow

The workflow uses the protected GitHub Environment `agent` in this repository and the `byor-private` self-hosted runner for private Terraform-state access. Bootstrap is configured for a separate container (`agent-tfstate-mykp`) and state key (`hosted-agent/mykp.tfstate`). Confirm the runner is registered for this repository before relying on CI deployment.

The plan-only workflow never applies. The deploy workflow creates the agent by default. Set `IMPORT_EXISTING_AGENT=true` only when `mykp-hosted-agent` already exists in this target project and the reviewed plan should import it.