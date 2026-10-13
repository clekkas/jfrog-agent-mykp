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

Before deployment, confirm JFrog's Azure OIDC mapping grants its project identity read access to `byor-demo-docker`, GitHub's OIDC mapping grants this repository deploy access to `byor-demo-docker-local`, and a `byor-private` runner is registered for this repository.

The workflow creates the logical agent by default. Set the environment variable `IMPORT_EXISTING_AGENT=true` only if `mykp-hosted-agent` already exists in this Foundry project and the plan is intended to import it.