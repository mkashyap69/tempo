output "api_url" {
  value = google_cloud_run_v2_service.api.uri
}

output "ios_app_id" {
  value = google_firebase_apple_app.ios.app_id
}

output "android_app_id" {
  value = google_firebase_android_app.android.app_id
}

output "workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github.name
}

output "deployer_service_account" {
  value = google_service_account.deployer.email
}

output "play_rtdn_topic" {
  description = "Paste into Play Console → Monetization setup → Real-time developer notifications."
  value       = google_pubsub_topic.play_rtdn.id
}
