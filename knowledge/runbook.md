<!-- scope: runbook, contract, valuesSha256, workflow_dispatch, deployment, image_uri, import_existing_agent, agent-tfstate-mykp, mykp.tfstate, reviewer, bootstrap, smoke test -->
# Runbook

Updated 2026-10-12. This repo owns the image build and hosted-agent release. The `jfrog-oidc-foundry` repo owns the Foundry registry connection and publishes the target project contract.

## Before bootstrap

1. Download the contract artifact from a successful foundation workflow for the target project. Verify `values.FOUNDRY_PROJECT_NAME` is `mysecond-project-for-kp` and check `valuesSha256`. Do not use the `workshop-demo-project` contract from `jfrog-agent-byor`. The current foundation checkout's `dev.tfvars` points to `workshop-demo-project`; if no target-specific artifact exists, the foundation owner must configure and apply a target environment before bootstrap.
2. Confirm the contract's `FOUNDRY_PROJECT_RESOURCE_ID`, project endpoint, registry connection name, and JFrog URL/repository match this deployment.
3. Ask the JFrog administrator to allow the target project's managed identity to read the shared Docker repository and to allow GitHub OIDC from `clekkas/jfrog-agent-mykp` to publish to its local repository.
4. Ensure the `byor-private` self-hosted runner is registered and online for this GitHub repository; Terraform state is reachable only from the private network.

## Bootstrap

Run from this repository with Azure CLI and GitHub CLI access, using the target contract and the appropriate reviewer(s):

```powershell
./scripts/bootstrap-github-oidc.ps1 `
  -Repo clekkas/jfrog-agent-mykp `
  -ContractFile .\foundry-mykp.json `
  -StateStorageAccount tfstateb173d2d85c34 `
  -StateContainer agent-tfstate-mykp `
  -EnvName mykp `
  -AppName github-mykp-agent-deployer `
  -Reviewers <user-or-org/team>
```

The bootstrap creates the repo-scoped `agent` environment, deployment identity, RBAC, state container, and ignored `infra/hosted-agent/backend.hcl`. The contract JSON is ignored and must not be committed. Use the repository's existing reviewer policy; do not disable reviews unless the GitHub plan requires it and the owner accepts that risk.

## Deploy and verify

- Run `agent-plan.yml` manually with the immutable image digest when reviewing a candidate. It never applies.
- `deploy-agent.yml` builds, smoke-tests, pushes, resolves a digest, applies Terraform, and smoke-tests the target Responses endpoint on matching source changes or manual dispatch.
- The first deployment creates `mykp-hosted-agent`. Keep `IMPORT_EXISTING_AGENT=false` unless a same-named target-project agent already exists; if it does, set the variable to `true` only after reviewing the import plan.
- Verify the candidate version becomes active, its image matches the expected digest, and the Responses smoke test completes.

Never commit backend configuration, Terraform state, plan files, or project contract JSON.