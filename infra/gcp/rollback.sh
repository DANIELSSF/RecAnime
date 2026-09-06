#!/bin/sh
# Lists Cloud Run revisions, or sends all traffic back to one of them. Rolling back is instant and
# does not rebuild: the previous image is still in Artifact Registry.
#
# Usage, from the repository root:
#   set -a; . infra/gcp/.env.deploy; set +a
#   sh infra/gcp/rollback.sh                    # which revisions exist, and which sha each carries
#   sh infra/gcp/rollback.sh recanime-api-00007-abc
#
# A rollback does not undo a database migration: DB_MIGRATE_ON_START=true means the newer schema is
# already applied. The migrations are additive, so an older revision keeps working.
set -eu

# shellcheck source=infra/gcp/lib.sh
. "$(dirname "$0")/lib.sh"
load_deploy_env
require_recanime_config

if [ "$#" -eq 0 ]; then
    run gcloud run revisions list \
        --service "$SERVICE" \
        --region "$REGION" \
        --project "$PROJECT" \
        --format 'table(name,active,creationTimestamp,labels.version)'
    echo
    echo "then: sh infra/gcp/rollback.sh <revision>"
    exit 0
fi

run gcloud run services update-traffic "$SERVICE" \
    --region "$REGION" \
    --project "$PROJECT" \
    --to-revisions "$1=100"

echo "all traffic now goes to $1"
