output "lb_public_ip" {
  value       = [for ip in oci_load_balancer_load_balancer.ords.ip_address_details : ip.ip_address]
  description = "LB IP 주소 (Public 또는 Private)"
}

output "lb_ocid" {
  value = oci_load_balancer_load_balancer.ords.id
}

output "cert_ocid" {
  value       = local.effective_cert_ocid
  description = "LB가 사용 중인 인증서 OCID (신규 import 또는 기존)"
}

output "healthcheck_url_sample" {
  value = "https://<LB_IP>${var.healthcheck_path}"
}
