#!/bin/sh
# One-time Google Cloud setup for the RecAnime API: APIs, runtime service account, Artifact
# Registry repository, the DATABASE_URL secret and the IAM bindings the build and the service need.
# Idempotent: safe to re-run (it also rotates the secret, see docs/runbook.md step 9).
#
# Usage, from the repository root, after creating the GCP project and linking billing:
#   set -a; . infra/gcp/.env.deploy; set +a
#   DATABASE_URL='postgres://...pooler.supabase.com:5432/postgres?sslmode=require' \
#     DRY_RUN=1 sh infra/gcp/bootstrap.sh   # prints the plan, changes nothing
#   DATABASE_URL='...' sh infra/gcp/bootstrap.sh
set -eu

# shellcheck source=infra/gcp/lib.sh
. "$(dirname "$0")/lib.sh"
load_deploy_env
require_recanime_config

: "${DATABASE_URL:?DATABASE_URL (the Supabase Supavisor *session* pooler string) is required}"
case "$DATABASE_URL" in
    *pooler.supabase.com:5432*) ;;
    *) echo "warning: DATABASE_URL is not a Supavisor session-pooler URL (pooler.supabase.com:5432)." >&2
       echo "         Cloud Run has no IPv6 egress and DB_SESSION_LOCK=true needs session mode." >&2 ;;
esac
case "$DATABASE_URL" in
    *sslmode=require*) ;;
    *) echo "warning: DATABASE_URL has no sslmode=require." >&2 ;;
esac

SA="${SERVICE}@${PROJECT}.iam.gserviceaccount.com"
REPO=recanime

echo "==> 1/5 enabling APIs"
run gcloud services enable \
    run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com \
    --project "$PROJECT"

echo "==> 2/5 runtime service account $SA"
if check gcloud iam service-accounts describe "$SA" --project "$PROJECT"; then
    echo "    already exists"
else
    run gcloud iam service-accounts create "$SERVICE" \
        --display-name "RecAnime API" \
        --project "$PROJECT"
fi

echo "==> 3/5 Artifact Registry repository $REPO ($REGION)"
if check gcloud artifacts repositories describe "$REPO" --location "$REGION" --project "$PROJECT"; then
    echo "    already exists"
else
    run gcloud artifacts repositories create "$REPO" \
        --repository-format docker \
        --location "$REGION" \
        --description "RecAnime API container images" \
        --project "$PROJECT"
fi
# Keeps the 5 most recent versions and deletes untagged ones older than 30 days.
run gcloud artifacts repositories set-cleanup-policies "$REPO" \
    --location "$REGION" \
    --project "$PROJECT" \
    --policy "$REPO_ROOT/infra/gcp/ar-cleanup-policy.json" \
    --no-dry-run

echo "==> 4/5 Secret Manager recanime-database-url"
if check gcloud secrets describe recanime-database-url --project "$PROJECT"; then
    secret_stdin gcloud secrets versions add recanime-database-url --data-file=- --project "$PROJECT"
else
    secret_stdin gcloud secrets create recanime-database-url --data-file=- --replication-policy automatic --project "$PROJECT"
fi

echo "==> 5/5 IAM"
run gcloud secrets add-iam-policy-binding recanime-database-url \
    --member "serviceAccount:$SA" \
    --role roles/secretmanager.secretAccessor \
    --project "$PROJECT"
echo "    granted roles/secretmanager.secretAccessor on recanime-database-url to $SA"

# Cloud Build pushes the image; without an explicit grant the default compute service account
# cannot write to a repository in another region's Artifact Registry.
if [ "${DRY_RUN:-0}" = "1" ]; then
    echo "# probe: gcloud projects describe $PROJECT --format value(projectNumber)"
    PROJECT_NUMBER='<projectNumber>'
else
    PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format 'value(projectNumber)')"
fi
BUILD_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
run gcloud artifacts repositories add-iam-policy-binding "$REPO" \
    --location "$REGION" \
    --project "$PROJECT" \
    --member "serviceAccount:$BUILD_SA" \
    --role roles/artifactregistry.writer
echo "    granted roles/artifactregistry.writer on $REPO to $BUILD_SA"
# Projects created since 2024 no longer hand roles/editor to the default compute service account,
# and cloudbuild.yaml logs to Cloud Logging only: without this the very first build fails.
run gcloud projects add-iam-policy-binding "$PROJECT" \
    --member "serviceAccount:$BUILD_SA" \
    --role roles/logging.logWriter \
    --condition None
echo "    granted roles/logging.logWriter on $PROJECT to $BUILD_SA"

echo
echo "bootstrap complete for $PROJECT. Next: sh infra/gcp/deploy.sh"
