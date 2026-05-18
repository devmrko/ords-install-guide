# ============================================================
# main.tf
# - 사설 인증서를 OCI Certificate Service 에 import (선택)
# - OCI Load Balancer (Flexible) 생성
# - HTTPS(443) listener → backend set → ORDS 노드들로 라우팅
# - HTTP(80) listener → 자동으로 HTTPS 리다이렉트
# ============================================================
terraform {
  required_version = ">= 1.3"
  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 5.0"
    }
  }

  # ============================================================
  # 보안 경고
  # state 파일에는 cert_pem / key_pem 이 평문 저장됨.
  # 로컬 backend(기본) 사용 시 디스크에 그대로 남음.
  # → 운영에서는 반드시 backend.tf.example 참고하여 원격 암호화 backend 로.
  # ============================================================
}

# Provider 는 환경의 ~/.oci/config 자동 인식 (oci setup config 먼저)
provider "oci" {}

locals {
  ords_node_ips = split(" ", trimspace(var.ords_nodes))
  # import_cert=true 면 새 리소스의 id, false 면 미리 받은 cert_ocid
  effective_cert_ocid = var.import_cert ? oci_certificates_management_certificate.private[0].id : var.cert_ocid
}

# ------------------------------------------------------------
# 사설 인증서 import (선택)
# ------------------------------------------------------------
resource "oci_certificates_management_certificate" "private" {
  count          = var.import_cert ? 1 : 0
  compartment_id = var.compartment_ocid
  name           = var.cert_name
  description    = "ORDS LB private TLS cert (imported via Terraform)"

  certificate_config {
    config_type        = "IMPORTED"
    cert_chain_pem     = var.chain_pem != "" ? var.chain_pem : null
    certificate_pem    = var.cert_pem
    private_key_pem    = var.key_pem
  }

  # 다른 서비스가 이 cert 를 참조 중이면 destroy 로 의도치 않게 사라지지 않게 보호.
  # 정말 지우려면 이 lifecycle 블록 제거 후 destroy 또는 `terraform state rm`.
  lifecycle {
    prevent_destroy = true
  }
}

# ------------------------------------------------------------
# Load Balancer
# ------------------------------------------------------------
resource "oci_load_balancer_load_balancer" "ords" {
  compartment_id = var.compartment_ocid
  display_name   = "ords-lb"
  shape          = var.lb_shape
  subnet_ids     = [var.subnet_ocid]
  is_private     = var.lb_is_private

  dynamic "shape_details" {
    for_each = var.lb_shape == "flexible" ? [1] : []
    content {
      minimum_bandwidth_in_mbps = var.lb_bw_min
      maximum_bandwidth_in_mbps = var.lb_bw_max
    }
  }
}

# ------------------------------------------------------------
# Backend set + ORDS 노드들
# ------------------------------------------------------------
resource "oci_load_balancer_backend_set" "ords" {
  load_balancer_id = oci_load_balancer_load_balancer.ords.id
  name             = "ords-bset"
  policy           = "ROUND_ROBIN"

  health_checker {
    protocol            = "HTTP"
    port                = var.ords_port
    url_path            = var.healthcheck_path
    return_code         = 200
    retries             = 3
    timeout_in_millis   = 3000
    interval_ms         = 10000
  }
}

resource "oci_load_balancer_backend" "ords_nodes" {
  for_each         = toset(local.ords_node_ips)
  load_balancer_id = oci_load_balancer_load_balancer.ords.id
  backendset_name  = oci_load_balancer_backend_set.ords.name
  ip_address       = each.value
  port             = var.ords_port
  weight           = 1
}

# ------------------------------------------------------------
# Listener — HTTPS 443 (사설 cert 사용)
# ------------------------------------------------------------
resource "oci_load_balancer_listener" "https" {
  load_balancer_id         = oci_load_balancer_load_balancer.ords.id
  name                     = "ords-https"
  default_backend_set_name = oci_load_balancer_backend_set.ords.name
  port                     = 443
  protocol                 = "HTTP"

  ssl_configuration {
    certificate_ids         = [local.effective_cert_ocid]
    verify_peer_certificate = false
  }
}

# ------------------------------------------------------------
# Listener — HTTP 80 → HTTPS 리다이렉트 룰셋
# ------------------------------------------------------------
resource "oci_load_balancer_rule_set" "redirect_to_https" {
  load_balancer_id = oci_load_balancer_load_balancer.ords.id
  name             = "redirect-http-to-https"

  items {
    action = "REDIRECT"
    conditions {
      attribute_name  = "PATH"
      attribute_value = "/"
      operator        = "FORCE_LONGEST_PREFIX_MATCH"
    }
    redirect_uri {
      protocol = "HTTPS"
      host     = "{host}"
      port     = 443
      path     = "{path}"
      query    = "{query}"
    }
    response_code = 301
  }
}

resource "oci_load_balancer_listener" "http_redirect" {
  load_balancer_id         = oci_load_balancer_load_balancer.ords.id
  name                     = "ords-http-redirect"
  default_backend_set_name = oci_load_balancer_backend_set.ords.name
  port                     = 80
  protocol                 = "HTTP"
  rule_set_names           = [oci_load_balancer_rule_set.redirect_to_https.name]
}
