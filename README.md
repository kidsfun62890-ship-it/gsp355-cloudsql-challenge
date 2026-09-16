# GSP355 — Create and Manage Cloud SQL for PostgreSQL Instances

Ye scripts sirf GSP355 lab ke lab-scoped resources ke liye hain. Lab ke Cloud Shell mein, lab student account ke saath, isi order mein run karo.

## Step 1 — postgres-vm prepare

```bash
curl -LO https://raw.githubusercontent.com/kidsfun62890-ship-it/gsp355-cloudsql-challenge/main/01-prepare-postgres-vm.sh
chmod +x 01-prepare-postgres-vm.sh
./01-prepare-postgres-vm.sh
```

## Step 2 — DMS profile aur continuous migration

```bash
curl -LO https://raw.githubusercontent.com/kidsfun62890-ship-it/gsp355-cloudsql-challenge/main/02-create-and-start-dms.sh
chmod +x 02-create-and-start-dms.sh
./02-create-and-start-dms.sh
```

DMS existing-instance workflow mein destination demotion/confirmation aur VPC peering allocation lab UI mein protected checkpoint ho sakta hai. Agar script DMS API error de, exact output bhejo; random retry mat karo. Migration data copy/CDC complete hone ke baad hi promote command run karo:

```bash
gcloud database-migration migration-jobs promote gsp355-orders-migration --region=europe-west1 --project=$(gcloud config get-value project) --no-async
```

## Step 3 — IAM authentication aur PITR

```bash
curl -LO https://raw.githubusercontent.com/kidsfun62890-ship-it/gsp355-cloudsql-challenge/main/03-iam-and-pitr.sh
chmod +x 03-iam-and-pitr.sh
./03-iam-and-pitr.sh
```

Expected lab values: migration user `migration_user`, password `DMS_1s_cool!`, destination `postgres33-uxoli`, IAM table `users`, PITR retention `7` days, clone `postgres-orders-pitr`.

## Expected time

Step 1: 5–10 minutes. Step 2: 20–40 minutes, mostly DMS full copy and CDC. Step 3: 5–10 minutes. Total usually 30–60 minutes; keep buffer inside the 1-hour lab timer.
