provider "google" {
  project = var.project_id
}

resource "google_project" "my_project" {
  name            = var.project_id
  project_id      = var.project_id
  billing_account = var.billing_account
  deletion_policy = "DELETE"
}
