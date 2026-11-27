# infra

Terraform for Tempo's two GCP projects (`tempo-dev`, `tempo-prod`), all in `asia-south1` (Mumbai, decision G-O1). Plan: `docs/research/Backend plan.md`.

## First time, per project (by hand)

1. Create the project, link billing, and make the state bucket:
   `gcloud storage buckets create gs://<project>-tfstate --location=asia-south1 --uniform-bucket-level-access`
2. `terraform init -backend-config="bucket=<project>-tfstate"`
3. `terraform apply -var-file=env/dev.tfvars` (or `prod`). The first apply runs the api on a placeholder image; CI deploys the real one.
4. Firebase console:
   - Authentication → Sign-in method: Anonymous, Apple, Google, Email link. **Don't** upgrade to Identity Platform (L-O2).
   - App Check: register, then turn on enforcement for Firestore, Storage and Authentication once real builds show verified traffic.
   - Download `GoogleService-Info.plist` and `google-services.json` for the app flavour.
5. Play Console: link the `tempo-api` service account (API access); point real-time developer notifications at the `play_rtdn_topic` output.
6. App Store Connect: App Store Server Notifications V2 URL = `<api_url>/webhooks/apple` (production and sandbox).
7. Set `PUSH_AUDIENCE` on the api to its own URL (the deploy workflow does this).

Not validated in the dev container (no Terraform binary there): run `terraform fmt -check && terraform validate` before the first apply. TODO(verify).
