locals {
  services = [
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "billingbudgets.googleapis.com",
    "cloudscheduler.googleapis.com",
    "firebase.googleapis.com",
    "firebaseappcheck.googleapis.com",
    "firebaserules.googleapis.com",
    "firebasestorage.googleapis.com",
    "firestore.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "identitytoolkit.googleapis.com", # plain Firebase Auth; no Identity Platform upgrade (L-O2)
    "androidpublisher.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "sts.googleapis.com",
  ]
  api_url = google_cloud_run_v2_service.api.uri
}

resource "google_project_service" "s" {
  for_each           = toset(local.services)
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "this" {}

# ---- Firebase project and apps ------------------------------------------

resource "google_firebase_project" "this" {
  provider   = google-beta
  project    = var.project_id
  depends_on = [google_project_service.s]
}

resource "google_firebase_apple_app" "ios" {
  provider     = google-beta
  display_name = "Tempo iOS (${var.env})"
  bundle_id    = var.ios_bundle_id
  team_id      = var.apple_team_id == "" ? null : var.apple_team_id
  depends_on   = [google_firebase_project.this]
}

resource "google_firebase_android_app" "android" {
  provider      = google-beta
  display_name  = "Tempo Android (${var.env})"
  package_name  = var.android_package
  sha256_hashes = var.android_sha256_fingerprints
  depends_on    = [google_firebase_project.this]
}

resource "google_firebase_app_check_app_attest_config" "ios" {
  provider   = google-beta
  app_id     = google_firebase_apple_app.ios.app_id
  token_ttl  = "3600s"
  count      = var.apple_team_id == "" ? 0 : 1
  depends_on = [google_project_service.s]
}

resource "google_firebase_app_check_play_integrity_config" "android" {
  provider   = google-beta
  app_id     = google_firebase_android_app.android.app_id
  token_ttl  = "3600s"
  depends_on = [google_project_service.s]
}

# Enforcement for Firestore, Storage and Auth is switched on in the console
# after the first app builds send valid tokens (turning it on first locks
# every client out). TODO(verify): google_firebase_app_check_service_config
# once all three report verified traffic.

# ---- Firestore ------------------------------------------------------------

resource "google_firestore_database" "default" {
  name                              = "(default)"
  location_id                       = var.region
  type                              = "FIRESTORE_NATIVE"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state           = var.env == "prod" ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  depends_on                        = [google_project_service.s]
}

resource "google_firestore_index" "purchases_by_uid" {
  collection = "purchases"
  fields {
    field_path = "uid"
    order      = "ASCENDING"
  }
  fields {
    field_path = "updatedAt"
    order      = "ASCENDING"
  }
  depends_on = [google_firestore_database.default]
}

resource "google_firestore_index" "purchases_recheck" {
  collection = "purchases"
  fields {
    field_path = "state"
    order      = "ASCENDING"
  }
  fields {
    field_path = "plan"
    order      = "ASCENDING"
  }
  fields {
    field_path = "updatedAt"
    order      = "ASCENDING"
  }
  depends_on = [google_firestore_database.default]
}

resource "google_firebaserules_ruleset" "firestore" {
  source {
    files {
      name    = "firestore.rules"
      content = file("${path.module}/../backend/rules/firestore.rules")
    }
  }
  depends_on = [google_firestore_database.default]
}

resource "google_firebaserules_release" "firestore" {
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore.name
}

# ---- Cloud Storage --------------------------------------------------------

resource "google_storage_bucket" "sync" {
  name                        = "${var.project_id}-sync"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning {
    enabled = true
  }
  # Superseded segments (compaction) stay 30 days, then go.
  lifecycle_rule {
    condition {
      days_since_noncurrent_time = 30
      with_state                 = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }
  depends_on = [google_project_service.s]
}

resource "google_firebase_storage_bucket" "sync" {
  provider  = google-beta
  bucket_id = google_storage_bucket.sync.name
}

resource "google_firebaserules_ruleset" "storage" {
  source {
    files {
      name    = "storage.rules"
      content = file("${path.module}/../backend/rules/storage.rules")
    }
  }
  depends_on = [google_firebase_storage_bucket.sync]
}

resource "google_firebaserules_release" "storage" {
  name         = "firebase.storage/${google_storage_bucket.sync.name}"
  ruleset_name = google_firebaserules_ruleset.storage.name
}

resource "google_storage_bucket" "feedback" {
  name                        = "${var.project_id}-feedback"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  # G-O6: feedback attachments are deleted after 90 days.
  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type = "Delete"
    }
  }
}

resource "google_storage_bucket" "exports" {
  name                        = "${var.project_id}-firestore-exports"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  lifecycle_rule {
    condition {
      age = 35
    }
    action {
      type = "Delete"
    }
  }
}

# ---- BigQuery -------------------------------------------------------------

resource "google_bigquery_dataset" "events" {
  dataset_id                  = "events"
  location                    = var.region
  default_table_expiration_ms = null
  depends_on                  = [google_project_service.s]
}

resource "google_bigquery_table" "app_events" {
  dataset_id          = google_bigquery_dataset.events.dataset_id
  table_id            = "app_events"
  deletion_protection = var.env == "prod"
  time_partitioning {
    type          = "DAY"
    field         = "at"
    expiration_ms = 395 * 24 * 3600 * 1000 # 13 months
  }
  schema = jsonencode([
    { name = "install_id", type = "STRING", mode = "REQUIRED" },
    { name = "app_version", type = "STRING", mode = "REQUIRED" },
    { name = "platform", type = "STRING", mode = "REQUIRED" },
    { name = "name", type = "STRING", mode = "REQUIRED" },
    { name = "at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "props", type = "JSON", mode = "NULLABLE" },
  ])
}

resource "google_bigquery_dataset" "billing" {
  dataset_id = "billing"
  location   = var.region
  depends_on = [google_project_service.s]
}

# ---- Service accounts and IAM ---------------------------------------------

resource "google_service_account" "api" {
  account_id   = "tempo-api"
  display_name = "Tempo api (Cloud Run)"
}

resource "google_service_account" "jobs" {
  account_id   = "tempo-jobs"
  display_name = "Tempo jobs (deletions, recheck)"
}

resource "google_service_account" "pusher" {
  account_id   = "tempo-pubsub-push"
  display_name = "Pub/Sub push to api"
}

resource "google_service_account" "scheduler" {
  account_id   = "tempo-scheduler"
  display_name = "Cloud Scheduler runs the jobs"
}

resource "google_service_account" "deployer" {
  account_id   = "tempo-deployer"
  display_name = "GitHub Actions deploys"
}

resource "google_project_iam_member" "api" {
  for_each = toset([
    "roles/datastore.user",
    "roles/firebaseappcheck.tokenVerifier",
    "roles/logging.logWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.api.email}"
}

resource "google_project_iam_member" "jobs" {
  for_each = toset([
    "roles/datastore.user",
    "roles/firebaseauth.admin", # delete the Auth user on account deletion
    "roles/logging.logWriter",
  ])
  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.jobs.email}"
}

resource "google_storage_bucket_iam_member" "api_feedback" {
  bucket = google_storage_bucket.feedback.name
  role   = "roles/storage.objectCreator"
  member = "serviceAccount:${google_service_account.api.email}"
}

resource "google_storage_bucket_iam_member" "jobs_sync" {
  bucket = google_storage_bucket.sync.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.jobs.email}"
}

resource "google_bigquery_dataset_iam_member" "api_events" {
  dataset_id = google_bigquery_dataset.events.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.api.email}"
}

# The api's service account is linked in Play Console → Setup → API access
# with "View financial data" and "Manage orders and subscriptions"; no key.

# ---- Artifact Registry ----------------------------------------------------

resource "google_artifact_registry_repository" "tempo" {
  repository_id = "tempo"
  location      = var.region
  format        = "DOCKER"
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }
  depends_on = [google_project_service.s]
}

# ---- Cloud Run ------------------------------------------------------------

locals {
  image = var.api_image != "" ? var.api_image : "us-docker.pkg.dev/cloudrun/container/hello"
  common_env = {
    GOOGLE_CLOUD_PROJECT = var.project_id
    PLAY_PACKAGE_NAME    = var.android_package
    APPLE_BUNDLE_ID      = var.ios_bundle_id
    SYNC_BUCKET          = google_storage_bucket.sync.name
    FEEDBACK_BUCKET      = google_storage_bucket.feedback.name
  }
}

resource "google_cloud_run_v2_service" "api" {
  name                = "api"
  location            = var.region
  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = var.env == "prod"
  template {
    service_account = google_service_account.api.email
    scaling {
      min_instance_count = 0 # scales to zero; webhooks tolerate a cold start
      max_instance_count = 10
    }
    containers {
      image = local.image
      resources {
        limits   = { cpu = "1", memory = "512Mi" }
        cpu_idle = true
      }
      dynamic "env" {
        for_each = merge(local.common_env, {
          PUSH_SERVICE_ACCOUNT = google_service_account.pusher.email
          BETA_GRANT_UNTIL     = var.beta_grant_until
        })
        content {
          name  = env.key
          value = env.value
        }
      }
      # PUSH_AUDIENCE is the service's own URL, known only after creation;
      # CI sets it on deploy (gcloud run services update --update-env-vars).
    }
  }
  lifecycle {
    ignore_changes = [template[0].containers[0].image, client, client_version]
  }
  depends_on = [google_project_service.s]
}

# The app calls api with Firebase ID and App Check tokens, checked in code.
resource "google_cloud_run_v2_service_iam_member" "public" {
  name     = google_cloud_run_v2_service.api.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_job" "job" {
  for_each            = toset(["deletions", "recheck"])
  name                = each.value
  location            = var.region
  deletion_protection = false
  template {
    template {
      service_account = google_service_account.jobs.email
      max_retries     = 1
      timeout         = "1800s"
      containers {
        image = local.image
        dynamic "env" {
          for_each = merge(local.common_env, { TEMPO_JOB = each.value, PUSH_AUDIENCE = "unused", PUSH_SERVICE_ACCOUNT = "unused" })
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [template[0].template[0].containers[0].image, client, client_version]
  }
  depends_on = [google_project_service.s]
}

resource "google_cloud_run_v2_job_iam_member" "scheduler" {
  for_each = google_cloud_run_v2_job.job
  name     = each.value.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

resource "google_cloud_scheduler_job" "run" {
  for_each = {
    deletions = "*/30 * * * *" # deletions finish within minutes
    recheck   = "17 3 * * *"   # daily entitlement re-check, 03:17 IST
  }
  name      = "run-${each.key}"
  region    = var.region
  schedule  = each.value
  time_zone = "Asia/Kolkata"
  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${each.key}:run"
    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }
  depends_on = [google_cloud_run_v2_job.job]
}

# ---- Play real-time developer notifications ---------------------------------

resource "google_pubsub_topic" "play_rtdn" {
  name       = "play-rtdn"
  depends_on = [google_project_service.s]
}

# Play publishes as this Google-owned account (Play Console → Monetization setup).
resource "google_pubsub_topic_iam_member" "play_publisher" {
  topic  = google_pubsub_topic.play_rtdn.name
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:google-play-developer-notifications@system.gserviceaccount.com"
}

resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.pusher.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription" "play_rtdn_push" {
  name                 = "play-rtdn-to-api"
  topic                = google_pubsub_topic.play_rtdn.id
  ack_deadline_seconds = 30
  push_config {
    push_endpoint = "${local.api_url}/workers/play-rtdn"
    oidc_token {
      service_account_email = google_service_account.pusher.email
      audience              = local.api_url
    }
  }
  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.play_rtdn_dead.id
    max_delivery_attempts = 20
  }
}

resource "google_pubsub_topic" "play_rtdn_dead" {
  name = "play-rtdn-dead"
}

# ---- CI: GitHub Actions through Workload Identity Federation -----------------

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github"
  depends_on                = [google_project_service.s]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }
  attribute_condition = "assertion.repository == \"${var.github_repo}\""
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "deployer_wif" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

resource "google_project_iam_member" "deployer" {
  for_each = toset(["roles/run.developer", "roles/artifactregistry.writer"])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.deployer.email}"
}

resource "google_service_account_iam_member" "deployer_acts_as" {
  for_each           = { api = google_service_account.api.name, jobs = google_service_account.jobs.name }
  service_account_id = each.value
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
}

# ---- Cost guard (launch plan → Cost levers 3) ------------------------------

resource "google_monitoring_notification_channel" "budget" {
  for_each     = toset(var.budget_emails)
  display_name = "Budget ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }
}

resource "google_billing_budget" "monthly" {
  count           = var.billing_account == "" ? 0 : 1
  billing_account = var.billing_account
  display_name    = "tempo-${var.env} monthly"
  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }
  amount {
    specified_amount {
      currency_code = "USD"
      units         = tostring(var.monthly_budget_usd)
    }
  }
  dynamic "threshold_rules" {
    for_each = [0.5, 0.9, 1.0]
    content {
      threshold_percent = threshold_rules.value
    }
  }
  all_updates_rule {
    monitoring_notification_channels = [for c in google_monitoring_notification_channel.budget : c.id]
  }
}
