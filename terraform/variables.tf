variable "compartment_ocid" { type = string }
variable "subnet_ocid"      { type = string }
variable "region" {
  description = "OCI region (예: ap-seoul-1). 빈 값이면 ~/.oci/config DEFAULT 프로파일 region 사용"
  type        = string
  default     = ""
}

variable "ords_nodes" {
  description = "공백 구분된 ORDS 노드 IP 리스트 (예: '10.0.1.11 10.0.1.12')"
  type        = string
}
variable "ords_port" {
  type    = number
  default = 8080
}
variable "healthcheck_path" {
  type    = string
  default = "/ords/_/landing"
}
variable "healthcheck_return_code" {
  description = "기대하는 HTTP 응답 코드. ORDS landing 은 인증 redirect 라 302."
  type        = number
  default     = 302
}

variable "lb_shape" {
  type    = string
  default = "flexible"
}
variable "lb_bw_min" {
  type    = number
  default = 10
}
variable "lb_bw_max" {
  type    = number
  default = 100
}
variable "lb_is_private" {
  type    = bool
  default = false
}

# --- 사설 인증서 ---
variable "import_cert" {
  description = "true 면 PEM 들로 새 cert 생성, false 면 cert_ocid 사용"
  type        = bool
  default     = false
}
variable "cert_ocid" {
  type    = string
  default = ""
}
variable "cert_name" {
  type    = string
  default = "ords-private-cert"
}
variable "cert_pem" {
  type      = string
  default   = ""
  sensitive = true
}
variable "key_pem" {
  type      = string
  default   = ""
  sensitive = true
}
variable "chain_pem" {
  type      = string
  default   = ""
  sensitive = true
}
