#!/bin/sh
# Builds services/api into an Artifact Registry image tagged with the git sha and deploys that exact
# image to Cloud Run, then verifies that /healthz reports the sha it just deployed.
#
# Usage, from the repository root (infra/gcp/bootstrap.sh must have run once):
#   set -a; . infra/gcp/.env.deploy; set +a
#   DRY_RUN=1 sh infra/gcp/deploy.sh   # prints the plan, changes nothing
#   sh infra/gcp/deploy.sh
#
# ALLOW_DIRTY=1 deploys a working tree with uncommitted changes (the image would then not match
# the sha it is tagged with).
set -eu

# shellcheck source=infra/gcp/lib.sh
. "$(dirname "$0")/lib.sh"
load_deploy_env
require_recanime_config

: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required (set it in infra/gcp/.env.deploy)}"
: "${AUTH_ALLOWED_EMAILS:?AUTH_ALLOWED_EMAILS is required (set it in infra/gcp/.env.deploy)}"

if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ] && [ "${ALLOW_DIRTY:-0}" != "1" ]; then
    echo "refusing to deploy: the working tree is dirty, so the image would not match its sha tag." >&2
    echo "Commit first, or re-run with ALLOW_DIRTY=1." >&2
    git -C "$REPO_ROOT" status --short >&2
    exit 1
fi

VERSION="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
IMAGE="$REGION-docker.pkg.dev/$PROJECT/recanime/api"
SA="${SERVICE}@${PROJECT}.iam.gserviceaccount.com"

echo "deploying $SERVICE $VERSION -> $IMAGE:$VERSION"

echo "==> 1/3 build"
run gcloud builds submit "$REPO_ROOT/services/api" \
    --config "$REPO_ROOT/services/api/cloudbuild.yaml" \
    --substitutions "_IMAGE=$IMAGE,_VERSION=$VERSION" \
    --project "$PROJECT" \
    --region "$REGION"

# gcloud splits --set-env-vars on commas, and AUTH_ALLOWED_EMAILS is itself comma-separated.
# "^;^" switches the delimiter to ";" for this flag only; none of these values contain one.
case "$AUTH_ALLOWED_EMAILS" in
    *';'* | *' '* | *'^'*)
        echo "AUTH_ALLOWED_EMAILS must be comma-separated emails with no spaces or ';' (got '$AUTH_ALLOWED_EMAILS')" >&2
        exit 2
        ;;
esac
ENV_VARS="^;^APP_ENV=production;SUPABASE_PROJECT_REF=$SUPABASE_PROJECT_REF;AUTH_ALLOWED_EMAILS=$AUTH_ALLOWED_EMAILS;DB_MIGRATE_ON_START=true;LOG_LEVEL=info"

echo "==> 2/3 deploy"
run gcloud run deploy "$SERVICE" \
    --image "$IMAGE:$VERSION" \
    --region "$REGION" \
    --project "$PROJECT" \
    --allow-unauthenticated \
    --service-account "$SA" \
    --min-instances 0 --max-instances 1 \
    --cpu 1 --memory 256Mi --concurrency 40 --timeout 60 --port 8080 \
    --cpu-boost \
    --set-env-vars "$ENV_VARS" \
    --set-secrets "DATABASE_URL=recanime-database-url:latest" \
    --update-labels "version=$VERSION"

echo "==> 3/3 verify"
if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "# probe: gcloud run services describe $SERVICE --region $REGION --project $PROJECT --format value(status.url)"
    URL='https://<service>-<hash>.a.run.app'
    echo "# probe: curl -fsS --max-time 30 \$URL/healthz   # aborts unless .version == $VERSION"
    echo "# probe: curl -fsS --max-time 30 \$URL/readyz"
else
    URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --project "$PROJECT" --format 'value(status.url)')"
    # Fetch first and parse second, so a failed request reports as such instead of as a traceback.
    if ! HEALTH="$(curl -fsS --max-time 30 "$URL/healthz")"; then
        echo "deploy verification failed: $URL/healthz did not answer. Check the revision logs:" >&2
        echo "  gcloud run services logs read $SERVICE --region $REGION --project $PROJECT --limit 50" >&2
        exit 1
    fi
    DEPLOYED="$(printf '%s' "$HEALTH" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("version", ""))
except ValueError:
    print("<not json>")')"
    if [ "$DEPLOYED" != "$VERSION" ]; then
        echo "deploy verification failed: /healthz reports version '$DEPLOYED', expected '$VERSION'." >&2
        echo "The running revision is not the image just built. Roll back with:" >&2
        echo "  sh infra/gcp/rollback.sh            # list revisions" >&2
        echo "  sh infra/gcp/rollback.sh <revision> # send 100% of traffic back" >&2
        exit 1
    fi
    echo "    /healthz version=$DEPLOYED"
    printf '    /readyz '
    curl -fsS --max-time 30 "$URL/readyz"
    echo
fi

# In an xcconfig "//" starts a comment, so the URL has to be written as "https:/$()/host".
# shellcheck disable=SC2016  # "$()" is the literal xcconfig escape, not a substitution.
XCCONFIG_URL="$(printf '%s' "$URL" | sed 's#//#/$()/#')"

cat <<EOF

deployed: $URL

Two follow-ups, both manual:
  1. GitHub → Settings → Secrets and variables → Actions → Variables: API_BASE_URL = $URL
     (the keep-alive workflow fails until that variable exists).
  2. apple/Configs/Secrets.xcconfig, then rebuild the Release configuration of both apps:
     API_BASE_URL_RELEASE = $XCCONFIG_URL
EOF
