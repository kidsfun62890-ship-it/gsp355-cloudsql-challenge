#!/usr/bin/env bash
set -euo pipefail

# GSP355 Task 1: Prepare postgres-vm for PostgreSQL logical migration.
PROJECT_ID="$(gcloud config get-value project 2>/dev/null)"
[[ -n "${PROJECT_ID}" && "${PROJECT_ID}" != "(unset)" ]] || { echo "ERROR: Set the lab project first." >&2; exit 1; }

# Enable only the APIs named by the lab.
gcloud services enable datamigration.googleapis.com servicenetworking.googleapis.com --project="${PROJECT_ID}"

# Install pglogical and configure PostgreSQL on the lab VM.
gcloud compute ssh postgres-vm --project="${PROJECT_ID}" --zone="$(gcloud compute instances list --filter='name=postgres-vm' --format='value(zone)' | head -n1)" --command='sudo bash -s' <<'REMOTE'
set -euo pipefail
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-14-pglogical

CONF=/etc/postgresql/14/main/postgresql.conf
HBA=/etc/postgresql/14/main/pg_hba.conf
sed -i "s/^#\?shared_preload_libraries.*/shared_preload_libraries = 'pglogical'/" "$CONF"
sed -i "s/^#\?wal_level.*/wal_level = logical/" "$CONF"
sed -i "s/^#\?max_replication_slots.*/max_replication_slots = 10/" "$CONF"
sed -i "s/^#\?max_wal_senders.*/max_wal_senders = 10/" "$CONF"
grep -qE '^host[[:space:]]+all[[:space:]]+all[[:space:]]+0\.0\.0\.0/0' "$HBA" || echo 'host all all 0.0.0.0/0 md5' >> "$HBA"
systemctl restart postgresql

sudo -u postgres psql -v ON_ERROR_STOP=1 -d orders <<'SQL'
CREATE EXTENSION IF NOT EXISTS pglogical;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'migration_user') THEN
    CREATE ROLE migration_user WITH LOGIN REPLICATION PASSWORD 'DMS_1s_cool!';
  ELSE
    ALTER ROLE migration_user WITH LOGIN REPLICATION PASSWORD 'DMS_1s_cool!';
  END IF;
END $$;
GRANT CONNECT ON DATABASE orders TO migration_user;
GRANT USAGE ON SCHEMA public TO migration_user;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO migration_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO migration_user;
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE' LOOP
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY DEFAULT', r.table_name);
  END LOOP;
END $$;
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['distribution_centers','inventory_items','order_items','products','users'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=t AND column_name='id')
       AND NOT EXISTS (
         SELECT 1 FROM pg_constraint c
         JOIN pg_class cl ON cl.oid=c.conrelid
         JOIN pg_namespace n ON n.oid=cl.relnamespace
         WHERE c.contype='p' AND n.nspname='public' AND cl.relname=t
       ) THEN
      EXECUTE format('ALTER TABLE public.%I ADD PRIMARY KEY (id)', t);
    END IF;
  END LOOP;
END $$;
SQL
REMOTE

echo "Task 1 complete: postgres-vm prepared for DMS."
echo "Source VM internal IP: $(gcloud compute instances describe postgres-vm --zone="$(gcloud compute instances list --filter='name=postgres-vm' --format='value(zone)' | head -n1)" --format='value(networkInterfaces[0].networkIP)')"
echo "Source VM external IP: $(gcloud compute instances describe postgres-vm --zone="$(gcloud compute instances list --filter='name=postgres-vm' --format='value(zone)' | head -n1)" --format='value(networkInterfaces[0].accessConfigs[0].natIP)')"
