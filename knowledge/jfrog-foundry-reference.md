<!-- scope: jfrog, artifactory, registry, docker, repository, repositories, virtual repo, local repo, foundry, hosted agent, hosted agents, responses protocol, responses, bring your own registry, pull token, token exchange, oauth, oidc, entra, audience, issuer, identity mapping, connection, connections, sku, cpu, memory, version, versions, latest, endpoint, protocol, readiness, liveness, healthz, echo mode, model mode, azapi, data plane, byor-demo-docker, agent-mykp, oauth_token_exchange, registry_connection, mysecond-project-for-kp, mykp-hosted-agent, jfrog-registry-acct, mi_not_authorized -->
# JFrog and Foundry reference notes (condensed)

Written 2026-10-12. This covers only what this repository documents or implements, not general product behavior. If a question goes beyond it, say it is not covered. IDs are redacted on purpose.

## The bring-your-own-registry pull path

A Foundry hosted agent runs a container image. Here the image is stored in a private JFrog registry instead of Azure Container Registry. Two independent identities are involved:

- Push side: GitHub Actions authenticates to JFrog with GitHub OIDC (no stored credential) and pushes the image.
- Pull side: the Foundry project's managed identity gets an Entra token, exchanges it with JFrog for a short-lived pull token (OAuth token exchange), and pulls the image. The agent never holds a registry credential.

The pull side is configured by a Foundry connection of type `registry_connection` with mode `oauth_token_exchange`. The hosted agent references the connection by name. The deploy workflow re-checks the live connection (target, type and mode) before Terraform runs and fails if it does not match.

## Registry connection

- The connection used is `jfrog-registry-acct`. It is an account-level shared connection on `<foundry-account>`, shared to all projects, so it resolves by name from `mysecond-project-for-kp`. The project has no project-scoped registry connection.
- This repo does not create or change the connection. It only references it by name through `registry_connection_id`.
- Its target is the JFrog base URL `https://trialndswdc.jfrog.io`, stored in the variable `JF_URL`.
- The token exchange settings are stored as the variables `REGISTRY_TOKEN_AUDIENCE`, `REGISTRY_TOKEN_ENDPOINT` (`/access/api/v1/oidc/token`) and `REGISTRY_OIDC_PROVIDER_NAME` (`oidc-byor`). The deploy workflow does not need them; they are kept for the inventory.

## JFrog side (done by a JFrog administrator, outside Terraform and outside this repo)

1. Azure integration `oidc-byor` for the Foundry project identity: issuer is the tenant's Entra v2.0 URL, the audience matches the token audience of the connection, and an identity mapping ties the project managed identity (the `oid` claim) to a user or group with read permission on the Docker repository. Each project's identity needs its own mapping, so `mysecond-project-for-kp` is different from `workshop-demo-project`.
2. GitHub OIDC provider `github-oidc` with issuer `https://token.actions.githubusercontent.com`, and one identity mapping per repository. The claims JSON of a mapping is a single JSON object, for example `{"ref": "refs/heads/main", "repository": "clekkas/jfrog-agent-mykp"}`. Two repositories need two separate mappings; pasting two objects into one claims field is invalid. The ref claim is still present in tokens issued to environment-scoped jobs. The mapping needs read plus deploy or cache permission on the local Docker repository only.
3. Docker repositories: the virtual repository is `byor-demo-docker`, shared with the byor repo. Pushes land in its local repository `byor-demo-docker-local`, which is where the GitHub mapping needs deploy permission. This repo's images are `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp`. The byor repo uses the image name `agent` in the same repository.
4. Network reachability from Foundry's image pull path and from the build runner.

A JFrog 403 "failed to exchange OIDC token" in the build job's JFrog login means the GitHub mapping for this repo is missing or its claims do not match.

## Entra side

- The Entra app `Foundry-Registry-Agent` is the token audience. It has assignment required, so the project's managed identity must be assigned to it (default access role, id all zeros). Without the assignment, creating a hosted-agent version fails with `mi_not_authorized: The project managed identity is not authorized to acquire a token for the registry connection's audience application`.
- The identities of both `workshop-demo-project` and `mysecond-project-for-kp` are assigned. A new assignment can take a few minutes to take effect.

## Image rules

- Built for `linux/amd64`, base python:3.12-slim, non-root user (uid 10001), listens on `$PORT` which defaults to 8088. The wrong architecture pulls fine and then never becomes active.
- CI pushes the tag `sha-<7-char commit>`, resolves it to the JFrog `sha256` digest, and passes only the digest reference to Terraform. The workflow validates that the digest repository is under `JFROG_REPO` and the image name is `agent-mykp`.
- JFrog refuses to overwrite an existing tag (`unauthorized: No permission to overwrite manifest`). Rebuilding the same commit fails at push; deploy the existing tag with the `image_tag` input instead.

## The hosted agent in Foundry

- The logical agent is `mykp-hosted-agent`, a Foundry data-plane resource of type `Microsoft.Foundry/agents@v1`, managed with `azapi_data_plane_resource` in `infra/hosted-agent`. It has `prevent_destroy`.
- Changing the image creates a new version under the same agent; old versions stay in Foundry history. The endpoint routes all traffic to the latest version.
- The project endpoint is `https://<foundry-account>.services.ai.azure.com/api/projects/mysecond-project-for-kp`.
- Allowed sizes (SKUs) are CPU and memory pairs: 0.5 CPU with 1Gi, 1 with 2Gi, and 2 with 4Gi. The list is hardcoded in `main.tf` and also read from the variable `SUPPORTED_AGENT_SKUS`, so the two can drift. The default is 0.5 CPU with 1Gi.
- A new version has a state and must reach active; a failed state or a different image fails the smoke test.
- The platform-managed agent identity can reach project models by default, so no extra role assignment is needed for model mode.
- `IMPORT_EXISTING_AGENT` is false by default and creates the agent. If an earlier apply created the agent in Foundry but failed before Terraform saved it, the next apply fails with "Resource already exists". Set `IMPORT_EXISTING_AGENT` to `true` on the `agent` environment, deploy once, then set it back to `false`.

## The app (`app.py`)

- FastAPI service implementing Responses protocol 2.0.0: `POST /responses` (non-streaming and server-sent events streaming), alias `POST /v1/responses`, and `GET /healthz`, `/readiness` and `/liveness` for probes.
- The input may be a plain string or a message array. The reply is a Responses-shaped envelope with `output[].content[].output_text` plus the `output_text` convenience field.
- Echo mode (default): no model call, proves the registry plumbing. Model mode: set `AZURE_AI_MODEL_DEPLOYMENT_NAME` (here `gpt-5-mini`) and the agent calls the Responses API on the project endpoint with its own Entra identity; no keys are in the image. Reasoning models reject legacy sampling parameters, so none are sent.
- Knowledge: every `knowledge/*.md` file is copied into the image and added to the model instructions, whole files in alphabetical order up to 60,000 characters; files that do not fit are listed under `knowledge_truncated` in `/healthz`.
- Scope gate: before any model call, code checks that the question mentions a known term. Terms come from backticked names in the knowledge files, key lines, a built-in list of general words, and any `scope:` comment a file declares on its first line. A question with no known term gets the fixed reply "Not in the knowledge base. Checked by code; the model was not called." A question about a capital city is answered from the Capital Cities section of `azure-assets.md` by lookup, without the model.
- `/healthz` reports the agent name, the mode (echo or model) and the loaded knowledge files.

## Microsoft Learn caveat

The Microsoft Learn BYOR article specifies the protocol name and version (responses 2.0.0) but not the full wire contract for a self-built container. The envelope here follows the standard Responses shape. If Foundry's invoke returns a protocol error, capture the request body it sends and adjust `create_response`; the image pull path is unaffected.
