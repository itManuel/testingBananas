
#Enable APIs in the project
resource "google_project_service" "project_services" {
  project = var.project_id
  for_each = toset([
    "compute.googleapis.com",
    "dns.googleapis.com",
    "iap.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
    "networkservices.googleapis.com",
    "run.googleapis.com",
  ])
  service                    = each.key
  disable_dependent_services = false
  disable_on_destroy         = true

  timeouts {
    create = "5m"
    update = "10m"
  }
}

resource "google_cloud_run_service" "default" {
  depends_on = [google_project_service.project_services]
  name       = "example"
  location   = var.region
  project    = var.project_id

  template {
    spec {
      containers {
        image = "gcr.io/cloudrun/hello"
      }
    }
  }
}

resource "google_compute_region_network_endpoint_group" "cloudrun_front" {
  name                  = "cloudrun-frontend"
  project               = var.project_id
  network_endpoint_type = "SERVERLESS"
  region                = var.region
  cloud_run {
    service = google_cloud_run_service.default.name
  }
}

data "google_iam_policy" "noauth" {
  binding {
    role = "roles/run.invoker"
    members = [
      "allUsers",
    ]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_service.default.location
  project  = google_cloud_run_service.default.project
  service  = google_cloud_run_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}

// reserve a global ip
resource "google_compute_global_address" "default" {
  name       = "${var.environment}-address"
  project    = var.project_id
  depends_on = [google_project_service.project_services]

}

//ssl certificate
resource "google_compute_managed_ssl_certificate" "default" {
  provider = google-beta
  project  = var.project_id

  name = "${var.environment}-cert"
  managed {
    domains = [var.domain]
  }
}

// default backend service (cloudrun_front)
resource "google_compute_backend_service" "frontend" {
  name    = "${var.environment}-front"
  project = var.project_id

  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

  iap {
    enabled              = true
    oauth2_client_id     = var.oauth2_client_id
    oauth2_client_secret = var.oauth2_client_secret
  }

  backend {
    group = google_compute_region_network_endpoint_group.cloudrun_front.id
  }
}

// default url map to the default backend (cloudrun_front)
resource "google_compute_url_map" "default" {
  name = "${var.environment}-urlmap"
  host_rule {
    hosts        = ["${var.domain}"]
    path_matcher = "mysite"
  }
  default_service = google_compute_backend_service.frontend.id
  path_matcher {
    name            = "mysite"
    default_service = google_compute_backend_service.frontend.id
  }
}

resource "google_compute_target_https_proxy" "default" {
  name = "${var.environment}-https-proxy"

  url_map = google_compute_url_map.default.id
  ssl_certificates = [
    google_compute_managed_ssl_certificate.default.id
  ]
}

resource "google_compute_global_forwarding_rule" "default" {
  name = "${var.environment}-lb"

  target     = google_compute_target_https_proxy.default.id
  port_range = "443"
  ip_address = google_compute_global_address.default.address
}

// all to the https port:
resource "google_compute_url_map" "https_redirect" {
  project = var.project_id
  name    = "${var.environment}-https-redirect"

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

resource "google_compute_target_http_proxy" "https_redirect" {
  project = var.project_id
  name    = "${var.environment}-http-proxy"
  url_map = google_compute_url_map.https_redirect.id
}

resource "google_compute_global_forwarding_rule" "https_redirect" {
  name    = "${var.environment}-lb-http"
  project = var.project_id

  target     = google_compute_target_http_proxy.https_redirect.id
  port_range = "80"
  ip_address = google_compute_global_address.default.address
}


data "google_iam_policy" "iap" {
  binding {
    role = "roles/iap.httpsResourceAccessor"
    members = [
      "group:everyone@google.com", // a google group
      // "allAuthenticatedUsers" // anyone with a Google account (not recommended)
      "user:roger123@gmail.com",       // a particular user
    ]
  }
}

resource "google_iap_web_backend_service_iam_policy" "policy" {
  project             = var.project_id
  web_backend_service = google_compute_backend_service.frontend.name
  policy_data         = data.google_iam_policy.iap.policy_data
  depends_on = [
    google_compute_global_forwarding_rule.default
  ]
}

