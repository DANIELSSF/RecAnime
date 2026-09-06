#!/bin/sh
# Changes who may sign in, without rebuilding or redeploying the image: it only updates the
# AUTH_ALLOWED_EMAILS environment variable of the running Cloud Run service (a new revision).
# The list is authoritative — pass every allowed address, not just the new one.
#
# Usage, from the repository root:
#   set -a; . infra/gcp/.env.deploy; set +a
#   sh infra/gcp/allowlist.sh 'first@example.com,second@example.com'
#
# The addresses must also be OAuth test users in the Google Cloud consent screen.
set -eu

# shellcheck source=infra/gcp/lib.sh
. "$(dirname "$0")/lib.sh"

EMAILS="${1:-}"
if [ -z "$EMAILS" ]; then
    echo "usage: sh infra/gcp/allowlist.sh 'first@example.com,second@example.com'" >&2
    exit 2
fi
if ! printf '%s' "$EMAILS" |
    grep -Eq '^[^,@[:space:]]+@[^,@[:space:]]+\.[^,@[:space:]]+(,[^,@[:space:]]+@[^,@[:space:]]+\.[^,@[:space:]]+)*$'; then
    echo "refusing: '$EMAILS' is not a comma-separated list of email addresses (no spaces)." >&2
    exit 2
fi

load_deploy_env
require_recanime_config

# gcloud splits --update-env-vars on commas; "^;^" switches the delimiter for this flag only.
run gcloud run services update "$SERVICE" \
    --region "$REGION" \
    --project "$PROJECT" \
    --update-env-vars "^;^AUTH_ALLOWED_EMAILS=$EMAILS"

echo "allowlist is now: $EMAILS"
