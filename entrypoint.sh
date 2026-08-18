#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_PAT:?required}"
: "${GITHUB_REPO:?required}"

RUNNER_NAME_PREFIX="${RUNNER_NAME_PREFIX:-render-runner}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,render,linux,x64}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-/opt/actions-runner/_work}"

RUNNER_NAME="${RUNNER_NAME_PREFIX}-$(hostname)-$$"
CONFIGURED=false
CHILD_PID=""

cleanup() {
  if [ -n "$CHILD_PID" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    echo "Forwarding SIGTERM to run.sh (pid $CHILD_PID), letting in-flight job finish..."
    kill -TERM "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" || true
  fi
  if [ "$CONFIGURED" = true ]; then
    echo "Deregistering runner ${RUNNER_NAME}..."
    deregister || echo "Warning: deregistration failed (token may have expired or job already consumed it)"
  fi
  exit 0
}
trap cleanup SIGTERM SIGINT

mint_registration_token() {
  curl -sSf -X POST \
    -H "Authorization: token ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/registration-token" \
    | jq -r .token
}

mint_removal_token() {
  curl -sSf -X POST \
    -H "Authorization: token ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${GITHUB_REPO}/actions/runners/remove-token" \
    | jq -r .token
}

register() {
  local reg_token
  reg_token="$(mint_registration_token)"
  ./config.sh --unattended --ephemeral \
    --url "https://github.com/${GITHUB_REPO}" \
    --token "${reg_token}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --work "${RUNNER_WORKDIR}" \
    --replace
  CONFIGURED=true
}

deregister() {
  local rm_token
  rm_token="$(mint_removal_token)"
  ./config.sh remove --token "${rm_token}"
  CONFIGURED=false
}

FAILURES=0
while true; do
  if register; then
    FAILURES=0
  else
    FAILURES=$((FAILURES + 1))
    backoff=$(( FAILURES > 6 ? 300 : 5 * (2 ** (FAILURES - 1)) ))
    echo "Registration failed (${FAILURES} in a row). Backing off ${backoff}s..."
    sleep "$backoff"
    continue
  fi

  ./run.sh --once &
  CHILD_PID=$!
  wait "$CHILD_PID"
  RUN_EXIT=$?
  CHILD_PID=""
  CONFIGURED=false

  if [ "$RUN_EXIT" -ne 0 ]; then
    FAILURES=$((FAILURES + 1))
    backoff=$(( FAILURES > 6 ? 300 : 5 * (2 ** (FAILURES - 1)) ))
    echo "run.sh exited ${RUN_EXIT} (${FAILURES} failures in a row). Backing off ${backoff}s..."
    sleep "$backoff"
  else
    FAILURES=0
  fi
done
