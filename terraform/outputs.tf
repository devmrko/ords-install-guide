output "lb_public_ip" {
  value       = [for ip in oci_load_balancer_load_balancer.ords.ip_address_details : ip.ip_address]
  description = "LB IP 주소 (Public 또는 Private)"
}

output "lb_ocid" {
  value = oci_load_balancer_load_balancer.ords.id
}

output "cert_ref" {
  value = var.import_cert ? oci_load_balancer_certificate.private[0].certificate_name : var.cert_ocid
  description = "LB listener 가 참조 중인 cert (import_cert=true 면 LB-attached name, false 면 Cert Service OCID)"
}

output "healthcheck_url_sample" {
  value = "https://<LB_IP>${var.healthcheck_path}"
}
