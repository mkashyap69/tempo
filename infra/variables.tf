variable "project_id" {
  description = "tempo-dev or tempo-prod (projects created by hand, billing linked)."
  type        = string
}

variable "env" {
  description = "dev or prod"
  type        = string
  validation {
    condition     = contains(["dev", "prod"], var.env)
    error_message = "env is dev or prod"
  }
}

variable "region" {
  description = "Decision G-O1: India, Mumbai. Firestore's location can't change later."
  type        = string
  default     = "asia-south1"
}

variable "api_image" {
  description = "Image for api and the jobs, e.g. asia-south1-docker.pkg.dev/<project>/tempo/api:<sha>. Empty on the first apply, before an image exists."
  type        = string
  default     = ""
}

variable "ios_bundle_id" {
  type    = string
  default = "dev.tempo.tempo" # TODO(launch): the reverse-domain id (L1)
}

variable "android_package" {
  type    = string
  default = "dev.tempo.tempo" # TODO(launch): the reverse-domain id (L1)
}

variable "apple_team_id" {
  description = "Apple Developer team id, for App Attest."
  type        = string
  default     = ""
}

variable "android_sha256_fingerprints" {
  description = "Play App Signing and upload key SHA-256 fingerprints, for Play Integrity."
  type        = list(string)
  default     = []
}

variable "github_repo" {
  description = "owner/repo allowed to deploy through Workload Identity Federation."
  type        = string
  default     = "mkashyap69/tempo"
}

variable "billing_account" {
  description = "Billing account id for the budget alert; empty skips it."
  type        = string
  default     = ""
}

variable "monthly_budget_usd" {
  type    = number
  default = 50
}

variable "budget_emails" {
  description = "Emails for budget alerts (a Cloud Monitoring channel each)."
  type        = list(string)
  default     = []
}

variable "beta_grant_until" {
  description = "ISO time until which new accounts get Pro free (the beta); empty for none."
  type        = string
  default     = ""
}
