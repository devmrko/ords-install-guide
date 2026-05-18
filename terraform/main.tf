# ============================================================
# main.tf
# - OCI Load Balancer (Flexible) 생성
# - 사설 인증서를 LB 에 직접 attach (oci_load_balancer_certificate, import_cert=true)
#   또는 기존 OCI Certificate Service OCID 참조 (import_cert=false, cert_ocid)
# - HTTPS(443) listener → backend set → ORDS 노드들로 라우팅
# - HTTP(80) listener → HTTPS(443) 301 리다이렉트
#
# 주의 (provider v8.x 기준):
#   oci_certificates_management_certificate 리소스는 IMPORTED PEM 입력 미지원
#   (CSR/Internal CA 발급만 가능). PEM 직접 attach 가 필요한 케이스는
#   oci_load_balancer_certificate 가 정답. LB 종단이라 이걸로 충분.
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

# Provider 는 환경의 ~/.oci/config 자동 인식 (oci setup config 먼저).
# var.region 채우면 config DEFAULT 와 다른 region 강제 가능 (예: DEFAULT=us-ashburn 인데 ap-seoul 에 배포).
provider "oci" {
  region = var.region != "" ? var.region : null
}

locals {
  ords_node_ips = split(" ", trimspace(var.ords_nodes))
}

# ------------------------------------------------------------
# 사설 인증서 import — LB 에 직접 attach
# (provider v8 의 oci_certificates_management_certificate 는 IMPORTED PEM 미지원,
#  대신 LB 자체 cert 리소스가 PEM 직접 받음.)
# ------------------------------------------------------------
resource "oci_load_balancer_certificate" "private" {
  count             = var.import_cert ? 1 : 0
  load_balancer_id  = oci_load_balancer_load_balancer.ords.id
  certificate_name  = var.cert_name
  public_certificate = var.cert_pem
  private_key        = var.key_pem
  ca_certificate     = var.chain_pem != "" ? var.chain_pem : null

  lifecycle {
    create_before_destroy = true
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
    # ORDS /ords/_/landing 은 인증 필요 → 302 로 응답. 그것 자체로 "ORDS 살아있다"는 신호.
    return_code         = var.healthcheck_return_code
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

  # 두 가지 cert 출처 지원:
  #  - import_cert=true  → 위 oci_load_balancer_certificate 로 LB 에 직접 attach (certificate_name)
  #  - import_cert=false → 기존 OCI Certificate Service 에 등록된 cert 의 OCID 사용 (certificate_ids)
  ssl_configuration {
    certificate_name        = var.import_cert ? oci_load_balancer_certificate.private[0].certificate_name : null
    certificate_ids         = var.import_cert ? null : [var.cert_ocid]
    verify_peer_certificate = false
  }
}

# ------------------------------------------------------------
# Listener — HTTP 80 → HTTPS 리다이렉트 룰셋
# ------------------------------------------------------------
resource "oci_load_balancer_rule_set" "redirect_to_https" {
  load_balancer_id = oci_load_balancer_load_balancer.ords.id
  name             = "redirect_http_to_https"

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
