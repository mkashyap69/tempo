terraform {
  required_version = ">= 1.9"
  required_providers {
    google      = { source = "hashicorp/google", version = "~> 6.30" }
    google-beta = { source = "hashicorp/google-beta", version = "~> 6.30" }
  }
  # State in a bucket created once by hand per project:
  #   gcloud storage buckets create gs://<project>-tfstate --location=asia-south1 --uniform-bucket-level-access
  backend "gcs" {}
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project               = var.project_id
  region                = var.region
  user_project_override = true
  billing_project       = var.project_id
}
