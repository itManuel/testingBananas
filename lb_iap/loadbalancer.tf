provider "google" {
  project = var.project_id
}

resource "google_project" "my_project" {
  name            = var.project_id
  project_id      = var.project_id
  billing_account = var.billing_account
}

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
    //    "aiplatform.googleapis.com",
    //    "artifactregistry.googleapis.com",
    // "certificatemanager.googleapis.com",
    //    "cloudtrace.googleapis.com",
    // "container.googleapis.com",
    // "containerscanning.googleapis.com",
    //    "dataflow.googleapis.com",
    //    "dataproc.googleapis.com",

    //    "edgecache.googleapis.com",
    // "firestore.googleapis.com",
    //    "livestream.googleapis.com",
    //    "redis.googleapis.com",

    //    "secretmanager.googleapis.com",
    //    "speech.googleapis.com",
    //    "transcoder.googleapis.com",
    //    "videointelligence.googleapis.com",
    //    "vpcaccess.googleapis.com",
    //    "workflows.googleapis.com"
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

/*
resource "google_identity_platform_oauth_idp_config" "oauth_idp_config" {
  name          = "oidc.oauth-idp-config"
  display_name  = "Display Name"
  client_id     = "client-id"
  issuer        = "issuer"
  enabled       = true
  client_secret = "secret"
}
*/

// default backend service (cloudrun_front)
resource "google_compute_backend_service" "frontend" {
  name    = "${var.environment}-front"
  project = var.project_id

  protocol    = "HTTP"
  port_name   = "http"
  timeout_sec = 30

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

variable "environment" {
  type        = string
  description = "environment value"
}

variable "domain" {
  type        = string
  description = "load balancer domain"
}

variable "region" {
  type        = string
  description = "region"
}

variable "project_id" {
  type        = string
  description = "project id"
}

variable "dnsname" {
  type = string
}
variable "dns_name" {
  type = string
}

variable "dns_description" {
  type = string
}

variable "billing_account" {
  type = string
}

data "google_iam_policy" "iap" {
  binding {
    role = "roles/iap.httpsResourceAccessor"
    members = [
      // "group:everyone@google.com", // a google group
      "allAuthenticatedUsers" // anyone with a Google account (not recommended)
      //"user:john@google.com", // a particular user
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


//DNS
resource "google_dns_managed_zone" "gcpsandbox" {
  depends_on  = [google_project_service.project_services]
  project     = var.project_id
  name        = var.dnsname
  dns_name    = var.dns_name
  description = var.dns_description
}

resource "google_dns_record_set" "ricardito_gcpsandbox" {
  project      = var.project_id
  name         = google_dns_managed_zone.gcpsandbox.dns_name
  type         = "A"
  ttl          = 300
  managed_zone = google_dns_managed_zone.gcpsandbox.name
  rrdatas      = [google_compute_global_address.default.address]
}
