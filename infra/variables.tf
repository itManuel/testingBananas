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

variable "oauth2_client_id" {
  type      = string
  sensitive = true
}
variable "oauth2_client_secret" {
  type      = string
  sensitive = true
}
