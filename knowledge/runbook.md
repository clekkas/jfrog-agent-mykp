<!-- scope: runbook, workflow_dispatch, deployment, image_uri, import_existing_agent, agent-tfstate-mykp, mykp.tfstate, reviewer, bootstrap, smoke test -->
# Runbook

Updated 2026-10-12. This repo is self-contained: it owns the image build, the hosted-agent release, its GitHub environment, deploy identity, state container and runner. It uses the account-shared Foundry connection `jfrog-registry-acct`.

## Before bootstrap

1. Confirm the project lists the connection: `az rest --method get --url "https://management.azure.com<project-id>/connections/jfrog-registry-acct?api-version=2025-06-01"` (target `https://trialndswdc.jfrog.io`, `type=registry_connection`, `mode=oauth_token_exchange`).
2. Ask the JFrog administrator to allow the target project's managed identity (`6dbf0c22-f50c-4a01-98d9-2a14218abb2f`) to read `byor-demo-docker` and to allow GitHub OIDC from `clekkas/jfrog-agent-mykp` (ref `refs/heads/main`) to publish to `byor-demo-docker-local`.
3. Ensure the `byor-private` self-hosted runner is registered and online for this GitHub repository; Terraform state is reachable only from the private network.

## Bootstrap

```powershell
./scripts/bootstrap-github-oidc.ps1 -Repo clekkas/jfrog-agent-mykp -NoRequiredReviewers
```

Use `-Reviewers <user-or-org/team>` instead of `-NoRequiredReviewers` on a GitHub plan that supports required reviewers on private repos. The bootstrap creates the repo-scoped `agent` environment (deploys from `main` only), deployment identity, RBAC, state container `agent-tfstate-mykp`, and ignored `infra/hosted-agent/backend.hcl`.

## Deploy and verify

- Run `agent-plan.yml` manually with the immutable image digest when reviewing a candidate. It never applies.
- `deploy-agent.yml` builds, smoke-tests, pushes, resolves a digest, applies Terraform, and smoke-tests the target Responses endpoint on matching source changes or manual dispatch.
- The first deployment creates `mykp-hosted-agent`. Keep `IMPORT_EXISTING_AGENT=false` unless a same-named target-project agent already exists; if it does, set the variable to `true` only after reviewing the import plan.
- Verify the candidate version becomes active, its image matches the expected digest, and the Responses smoke test completes.

Never commit backend configuration, Terraform state or plan files.