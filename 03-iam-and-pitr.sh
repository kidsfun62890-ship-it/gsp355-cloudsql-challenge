#!/usr/bin/env bash
set -euo pipefail

# GSP355 Tasks 3-4: IAM table access and point-in-time recovery clone.
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
INSTANCE="postgres33-uxoli"
IAM_USER="$(gcloud config get-value account 2>/dev/null)"
VM_ZONE="$(gcloud compute instances list --filter='name=postgres-vm' --format='value(zone)' | head -n1)"
VM_IP="$(gcloud compute instances describe postgres-vm --zone="${VM_ZONE}" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"

[[ -n "${PROJECT_ID}" && "${PROJECT_ID}" != "(unset)" ]] || { echo "ERROR: Set the lab project first." >&2; exit 1; }

# Allow only the lab VM's public address, as required by the lab.
gcloud sql instances patch "${INSTANCE}" --project="${PROJECT_ID}" \
  --authorized-networks="${VM_IP}/32"

# Enable IAM database authentication and backups/PITR with seven retained days.
gcloud sql instances patch "${INSTANCE}" --project="${PROJECT_ID}" \
  --database-flags=cloudsql.iam_authentication=on \
  --backup-start-time=03:00 \
  --enable-point-in-time-recovery \
  --retained-transaction-log-days=7

gcloud sql users create "${IAM_USER}" --instance="${INSTANCE}" --type=cloud_iam_user \
  --project="${PROJECT_ID}" 2>/dev/null || echo "IAM user already exists; continuing."

IP="$(gcloud sql instances describe "${INSTANCE}" --project="${PROJECT_ID}" --format='value(ipAddresses[0].ipAddress)')"
export PGPASSWORD='supersecret!'
psql "sslmode=require user=postgres hostaddr=${IP} dbname=orders" \
  -c "GRANT SELECT ON TABLE users TO \"${IAM_USER}\";"

# Record a UTC timestamp, make the required post-timestamp database change, then clone.
TIME_STAMP="$(date -u --rfc-3339=ns | sed -r 's/ /T/; s/\.([0-9]{3}).*/.\1Z/')"
echo "PITR timestamp: ${TIME_STAMP}"
psql "sslmode=require user=postgres hostaddr=${IP} dbname=orders" \
  -c "INSERT INTO distribution_centers (name, latitude, longitude) VALUES ('pitr-test-center', 0, 0);"

# The clone name is required exactly by the lab.
gcloud sql instances clone "${INSTANCE}" postgres-orders-pitr \
  --point-in-time="${TIME_STAMP}" --project="${PROJECT_ID}" --quiet

echo "Task 3 and Task 4 automation complete. Test IAM login and refresh the lab score."
