#!/bin/sh
# Shared guards and helpers for the infra/gcp scripts. Sourced, never executed directly:
#
#   . "$(dirname "$0")/lib.sh"
#
# Two rules the callers must respect:
#   1. gcloud is pinned to the personal `recanime` configuration; the default configuration on this
#      machine belongs to a work account and must never be touched.
#   2. Every mutating command goes through `run`, so DRY_RUN=1 prints the whole plan without
#      executing anything. Read-only lookups go through `check` / an explicit DRY_RUN branch.

# Absolute paths, independent of the caller's working directory.
# shellcheck disable=SC2034  # REPO_ROOT is consumed by the scripts that source this file.
GCP_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$GCP_DIR/../.." && pwd)"

# run CMD [ARG...] — run the command, or print it when DRY_RUN=1.
run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '%s ' "$@"
        echo
    else
        "$@"
    fi
}

# check CMD [ARG...] — read-only existence probe (a `describe`). Returns 0 when the resource
# exists. Under DRY_RUN nothing is executed: the probe is printed and reported as "missing" so the
# create branch is printed too.
check() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        printf '# probe: '
        printf '%s ' "$@"
        echo
        return 1
    fi
    "$@" >/dev/null 2>&1
}

# secret_stdin CMD [ARG...] — run the command with $DATABASE_URL on stdin, so the secret never
# reaches a command line or the process table. Under DRY_RUN the command is printed without it.
secret_stdin() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        # shellcheck disable=SC2016  # printed as a literal: the secret must not appear.
        printf '$DATABASE_URL | '
        printf '%s ' "$@"
        echo
    else
        printf '%s' "$DATABASE_URL" | "$@"
    fi
}

# load_deploy_env — export the values in infra/gcp/.env.deploy when that file exists.
# Copy infra/gcp/.env.deploy.example to create it; it is gitignored.
load_deploy_env() {
    if [ -f "$GCP_DIR/.env.deploy" ]; then
        set -a
        # shellcheck source=/dev/null
        . "$GCP_DIR/.env.deploy"
        set +a
    fi
}

# require_recanime_config — pin gcloud to the `recanime` configuration and refuse to continue
# unless it is signed in as GCP_ACCOUNT and a project is known. Leaves ACCOUNT, PROJECT, REGION
# and SERVICE set for the calling script.
require_recanime_config() {
    export CLOUDSDK_ACTIVE_CONFIG_NAME=recanime
    : "${GCP_ACCOUNT:?GCP_ACCOUNT is required: the personal Google account that owns the RecAnime project (set it in infra/gcp/.env.deploy)}"

    REGION="${GCP_REGION:-us-east1}"
    # shellcheck disable=SC2034  # SERVICE is consumed by the scripts that source this file.
    SERVICE="${CLOUD_RUN_SERVICE:-recanime-api}"

    ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
    if [ "$ACCOUNT" != "$GCP_ACCOUNT" ]; then
        echo "refusing to continue: the 'recanime' gcloud configuration is signed in as '$ACCOUNT'," >&2
        echo "but GCP_ACCOUNT is '$GCP_ACCOUNT'. Fix one of the two; never use the default (work) configuration:" >&2
        echo "  gcloud config set account <personal account> --configuration=recanime" >&2
        exit 1
    fi

    CONFIGURED_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
    case "$CONFIGURED_PROJECT" in "(unset)") CONFIGURED_PROJECT="" ;; esac

    if [ -n "${GCP_PROJECT:-}" ] && [ -n "$CONFIGURED_PROJECT" ] && [ "$GCP_PROJECT" != "$CONFIGURED_PROJECT" ]; then
        echo "refusing to continue: GCP_PROJECT is '$GCP_PROJECT' but the 'recanime' configuration points at '$CONFIGURED_PROJECT'." >&2
        echo "Unset GCP_PROJECT or run: gcloud config set project $GCP_PROJECT --configuration=recanime" >&2
        exit 1
    fi

    PROJECT="${GCP_PROJECT:-$CONFIGURED_PROJECT}"
    if [ -z "$PROJECT" ]; then
        echo "refusing to continue: no GCP project. Create it first (see docs/runbook.md), then:" >&2
        echo "  gcloud config set project <project id> --configuration=recanime" >&2
        echo "or set GCP_PROJECT in infra/gcp/.env.deploy." >&2
        exit 1
    fi

    echo "project=$PROJECT region=$REGION account=$ACCOUNT"
}
