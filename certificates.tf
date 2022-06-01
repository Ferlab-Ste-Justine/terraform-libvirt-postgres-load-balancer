resource "tls_private_key" "patroni_client_key" {
  algorithm   = "RSA"
  rsa_bits = 4096
}

resource "tls_cert_request" "patroni_client_request" {
  private_key_pem = tls_private_key.patroni_client_key.private_key_pem

  subject {
    common_name  = "patroni-client"
  }
}

resource "tls_locally_signed_cert" "patroni_client_certificate" {
  cert_request_pem   = tls_cert_request.patroni_client_request.cert_request_pem
  ca_private_key_pem = var.haproxy.patroni_client.ca_key
  ca_cert_pem        = var.haproxy.patroni_client.ca_certificate

  validity_period_hours = var.haproxy.patroni_client.certificate_validity_period
  early_renewal_hours = var.haproxy.patroni_client.certificate_early_renewal_period

  allowed_uses = [
    "client_auth",
  ]

  is_ca_certificate = false
}