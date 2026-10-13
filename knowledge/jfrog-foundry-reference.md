<!-- scope: jfrog, artifactory, registry, docker, repository, byor-demo-docker, agent-mykp, oidc, token exchange, oauth_token_exchange, registry_connection, mysecond-project-for-kp, mykp-hosted-agent -->
# JFrog and Foundry Reference

Updated 2026-10-12. These notes describe the integration used by this agent. Secrets and credentials are never stored in the image or repository.

## Authentication paths

- **Image push:** GitHub Actions in `clekkas/jfrog-agent-mykp` authenticates to JFrog using the `JFROG_GITHUB_OIDC_PROVIDER` from the target contract. Its JFrog identity mapping needs read and deploy/cache permissions on the local Docker repository behind `JFROG_REPO`.
- **Image pull:** The managed identity of `mysecond-project-for-kp` exchanges an Entra token with JFrog for a short-lived pull token. Its JFrog mapping needs read access to the shared repository. This identity is different from the `workshop-demo-project` identity.
- **Registry connection:** The target Foundry project's `registry_connection` with `oauth_token_exchange` mode is owned by `jfrog-oidc-foundry`. This agent repo references the connection by the contract's `JFROG_REGISTRY_CONNECTION_NAME`; it must not create or modify the connection.

## Image path

The shared virtual Docker repository is `byor-demo-docker`; its local deployment repository is `byor-demo-docker-local`. This repo uses image name `agent-mykp`, producing `trialndswdc.jfrog.io/byor-demo-docker/agent-mykp:<tag>` before resolving to an immutable `@sha256:` digest. The reference repo uses a different image name to avoid same-tag collisions.

The exact JFrog host, repository, OIDC provider, connection name, audience, and target project principal must be read from the published target contract or verified by the platform/JFrog owner. Do not infer the project principal from the reference project.