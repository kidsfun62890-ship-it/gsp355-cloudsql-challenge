#!/usr/bin/env bash
set -euo pipefail

# GSP355 Task 1 continuation: Create DMS profiles and start continuous migration.
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
REGION="europe-west1"
DEST_INSTANCE="postgres33-uxoli"
SOURCE_PROFILE="postgres-vm-source"
DEST_PROFILE="postgres33-destination"
JOB_ID="gsp355-orders-migration"
ZONE="$(gcloud compute instances list --filter='name=postgres-vm' --format='value(zone)' | head -n1)"
SOURCE_IP="$(gcloud compute instances describe postgres-vm --zone="${ZONE}" --format='value(networkInterfaces[0].networkIP)')"
VPC="projects/${PROJECT_ID}/global/networks/default"

[[ -n "${PROJECT_ID}" && "${PROJECT_ID}" != "(unset)" ]] || { echo "ERROR: Set the lab project first." >&2; exit 1; }

if ! gcloud database-migration connection-profiles describe "${SOURCE_PROFILE}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud database-migration connection-profiles create postgresql "${SOURCE_PROFILE}" \
    --region="${REGION}" --role=SOURCE --host="${SOURCE_IP}" --port=5432 \
    --database=orders --username=migration_user --password='DMS_1s_cool!' \
    --display-name='postgres-vm source' --no-async --project="${PROJECT_ID}"
fi

if ! gcloud database-migration connection-profiles describe "${DEST_PROFILE}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud database-migration connection-profiles create postgresql "${DEST_PROFILE}" \
    --region="${REGION}" --role=DESTINATION --cloudsql-instance="${DEST_INSTANCE}" \
    --display-name='postgres33 existing destination' --no-async --project="${PROJECT_ID}"
fi

if ! gcloud database-migration migration-jobs describe "${JOB_ID}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null 2>&1; then
  gcloud database-migration migration-jobs create "${JOB_ID}" \
    --region="${REGION}" --display-name='GSP355 orders continuous migration' \
    --source="${SOURCE_PROFILE}" --destination="${DEST_PROFILE}" \
    --type=CONTINUOUS --databases-filter=orders --peer-vpc="${VPC}" \
    --no-async --project="${PROJECT_ID}"
fi

gcloud database-migration migration-jobs verify "${JOB_ID}" --region="${REGION}" --project="${PROJECT_ID}" --no-async || true
gcloud database-migration migration-jobs start "${JOB_ID}" --region="${REGION}" --project="${PROJECT_ID}" --no-async

echo "Continuous migration started. Wait until the job shows RUNNING/CDC and then run:"
echo "gcloud database-migration migration-jobs promote ${JOB_ID} --region=${REGION} --project=${PROJECT_ID} --no-async"
echo "Run that promote command only after the migration has copied the source data and the lab allows promotion."
