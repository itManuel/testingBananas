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
