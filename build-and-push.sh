#!/usr/bin/env bash
# Build the mykp agent image and push it to the shared JFrog repository.
#
#   export JFROG_HOST="yourtrial.jfrog.io"
#   export JFROG_REPO="foundry-agents"      # your Docker repo key in Artifactory
#   export IMAGE_TAG="0.1"
#   ./build-and-push.sh
#
set -euo pipefail

JFROG_HOST="${JFROG_HOST:?set JFROG_HOST, e.g. yourtrial.jfrog.io}"
JFROG_REPO="${JFROG_REPO:?set JFROG_REPO, e.g. foundry-agents}"
IMAGE_TAG="${IMAGE_TAG:-0.1}"
IMAGE="${JFROG_HOST}/${JFROG_REPO}/agent-mykp:${IMAGE_TAG}"

echo "==> Building ${IMAGE} (linux/amd64)"
docker build --platform linux/amd64 -t "${IMAGE}" .

echo "==> Smoke testing locally on :8088"
CID=$(docker run -d --rm -p 8088:8088 "${IMAGE}")
trap 'docker stop "${CID}" >/dev/null 2>&1 || true' EXIT
sleep 4
curl -fsS http://localhost:8088/healthz; echo
curl -fsS -X POST http://localhost:8088/responses \
  -H 'Content-Type: application/json' \
  -d '{"input":"Respond with a short deployment confirmation."}' | head -c 600; echo
docker stop "${CID}" >/dev/null
trap - EXIT

echo "==> Pushing to JFrog (docker login first if this fails)"
docker push "${IMAGE}"

echo
echo "Image pushed: ${IMAGE}"
echo "Use the resolved immutable digest with deploy.ps1 -Image or IMAGE=... ./deploy.sh."
