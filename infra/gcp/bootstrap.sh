#!/bin/sh
# One-time Google Cloud setup for the API (run after creating the project and enabling billing).
# Usage: DATABASE_URL='postgres://...pooler.supabase.com:5432/postgres?sslmode=require' sh infra/gcp/bootstrap.sh
set -eu
export CLOUDSDK_ACTIVE_CONFIG_NAME=recanime
PROJECT="$(gcloud config get-value project)"
SERVICE="${CLOUD_RUN_SERVICE:-recanime-api}"
: "${DATABASE_URL:?DATABASE_URL (Supavisor session pooler string) is required}"

gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com secretmanager.googleapis.com
gcloud iam service-accounts describe "${SERVICE}@${PROJECT}.iam.gserviceaccount.com" >/dev/null 2>&1 \
  || gcloud iam service-accounts create "$SERVICE" --display-name "RecAnime API"
if gcloud secrets describe recanime-database-url >/dev/null 2>&1; then
  printf '%s' "$DATABASE_URL" | gcloud secrets versions add recanime-database-url --data-file=-
else
  printf '%s' "$DATABASE_URL" | gcloud secrets create recanime-database-url --data-file=- --replication-policy=automatic
fi
gcloud secrets add-iam-policy-binding recanime-database-url \
  --member "serviceAccount:${SERVICE}@${PROJECT}.iam.gserviceaccount.com" \
  --role roles/secretmanager.secretAccessor >/dev/null
echo "bootstrap complete for $PROJECT"
