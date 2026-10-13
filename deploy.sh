#!/usr/bin/env bash
# Deploy the hosted agent with Terraform (AzAPI) from a workstation.
#
# Defaults target project mysecond-project-for-kp and the account-shared registry connection
# jfrog-registry-acct; override with PROJECT_ENDPOINT / REGISTRY_CONNECTION_NAME.
#
#   IMAGE=<host>/<repo>/agent-mykp@sha256:<digest> ./deploy.sh
#   AUTO_APPROVE=1 ... ./deploy.sh     # non-interactive
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_TF_DIR="${ROOT}/infra/hosted-agent"
AGENT_SERVICE="${AGENT_SERVICE:-mykp-hosted-agent}"
MODEL_DEPLOYMENT="${MODEL_DEPLOYMENT:-gpt-5-mini}"
IMPORT_EXISTING_AGENT="${IMPORT_EXISTING_AGENT:-false}"

PROJECT_ENDPOINT="${PROJECT_ENDPOINT:-https://kaiser-foundry-resource.services.ai.azure.com/api/projects/mysecond-project-for-kp}"
REGISTRY_CONNECTION_NAME="${REGISTRY_CONNECTION_NAME:-jfrog-registry-acct}"
[[ "${IMPORT_EXISTING_AGENT}" == "true" || "${IMPORT_EXISTING_AGENT}" == "false" ]] || {
  echo "IMPORT_EXISTING_AGENT must be true or false." >&2
  exit 1
}
[[ "${IMAGE:-}" =~ ^[^/]+/.+@sha256:[0-9a-f]{64}$ ]] || {
  echo "IMAGE must be digest-pinned (<host>/<repo>/<image>@sha256:<64 hex>), got '${IMAGE:-}'." >&2
  exit 1
}
[[ -f "${AGENT_TF_DIR}/backend.hcl" ]] || {
  echo "Missing ${AGENT_TF_DIR}/backend.hcl (remote state). Run scripts/bootstrap-github-oidc.ps1 first." >&2
  exit 1
}

echo "==> Terraform: hosted agent ${AGENT_SERVICE} (connection: ${REGISTRY_CONNECTION_NAME})"
terraform -chdir="${AGENT_TF_DIR}" init -input=false -backend-config=backend.hcl
terraform -chdir="${AGENT_TF_DIR}" plan -input=false -out=tfplan \
  -var="project_endpoint=${PROJECT_ENDPOINT}" \
  -var="agent_name=${AGENT_SERVICE}" \
  -var="image_uri=${IMAGE}" \
  -var="registry_connection_name=${REGISTRY_CONNECTION_NAME}" \
  -var="model_deployment_name=${MODEL_DEPLOYMENT}" \
  -var="import_existing_agent=${IMPORT_EXISTING_AGENT}"
if [[ "${AUTO_APPROVE:-0}" != "1" ]]; then
  read -r -p "Apply the hosted-agent plan? (y/N) " answer
  [[ "${answer}" =~ ^([yY]|[yY][eE][sS])$ ]] || { echo "Aborted."; exit 1; }
fi
terraform -chdir="${AGENT_TF_DIR}" apply -input=false tfplan
rm -f "${AGENT_TF_DIR}/tfplan"
echo "Hosted agent version: $(terraform -chdir="${AGENT_TF_DIR}" output -raw agent_version)"
