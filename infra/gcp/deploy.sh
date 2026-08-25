#!/bin/sh
# Deploys services/api to Cloud Run using the dedicated `recanime` gcloud configuration.
# Never touches the default (work) configuration. Required once:
#   gcloud config configurations create recanime --no-activate
#   gcloud config set account daniel.santiago730@gmail.com --configuration=recanime
#   gcloud config set project <RECANIME_GCP_PROJECT> --configuration=recanime
# Required env: SUPABASE_PROJECT_REF, AUTH_ALLOWED_EMAILS (comma separated).
# The DATABASE_URL secret must exist in Secret Manager as `recanime-database-url`.
set -eu

export CLOUDSDK_ACTIVE_CONFIG_NAME=recanime
REGION="${GCP_REGION:-us-east1}"
SERVICE="${CLOUD_RUN_SERVICE:-recanime-api}"
EXPECTED_ACCOUNT="${GCP_ACCOUNT:-daniel.santiago730@gmail.com}"

ACCOUNT="$(gcloud config get-value account 2>/dev/null || true)"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
  echo "refusing to deploy: gcloud configuration 'recanime' uses account '$ACCOUNT' (expected $EXPECTED_ACCOUNT)" >&2
  exit 1
fi
if [ -z "$PROJECT" ]; then
  echo "refusing to deploy: no project set in the 'recanime' gcloud configuration" >&2
  exit 1
fi
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF is required}"
: "${AUTH_ALLOWED_EMAILS:?AUTH_ALLOWED_EMAILS is required}"

VERSION="$(git rev-parse --short HEAD 2>/dev/null || echo dev)"
SA="${SERVICE}@${PROJECT}.iam.gserviceaccount.com"

echo "deploying $SERVICE ($VERSION) to $PROJECT/$REGION as $ACCOUNT"
gcloud run deploy "$SERVICE" \
  --source services/api \
  --region "$REGION" \
  --allow-unauthenticated \
  --service-account "$SA" \
  --min-instances 0 --max-instances 1 \
  --cpu 1 --memory 256Mi --concurrency 40 --timeout 60 --port 8080 \
  --set-env-vars "APP_ENV=production,SUPABASE_PROJECT_REF=${SUPABASE_PROJECT_REF},AUTH_ALLOWED_EMAILS=${AUTH_ALLOWED_EMAILS},DB_MIGRATE_ON_START=true,LOG_LEVEL=info" \
  --set-secrets "DATABASE_URL=recanime-database-url:latest" \
  --set-build-env-vars "VERSION=${VERSION}"

URL="$(gcloud run services describe "$SERVICE" --region "$REGION" --format 'value(status.url)')"
echo "deployed: $URL"
curl -fsS "$URL/healthz" && echo
