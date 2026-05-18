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

# create_network=true 일 때만 채워짐. 사용자가 ORDS VM 띄울 때 이 OCID 들 참조.
output "vcn_ocid" {
  value       = var.create_network ? oci_core_vcn.ords[0].id : null
  description = "신규 생성된 VCN OCID (create_network=true 일 때만)"
}
output "subnet_ocid" {
  value       = local.effective_subnet_ocid
  description = "LB 가 쓰는 subnet OCID (신규 또는 var.subnet_ocid)"
}
