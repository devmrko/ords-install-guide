variable "compartment_ocid" { type = string }
variable "region" {
  description = "OCI region (예: ap-seoul-1). 빈 값이면 ~/.oci/config DEFAULT 프로파일 region 사용"
  type        = string
  default     = ""
}

# --- Network (선택 — create_network=true 면 VCN 까지 새로 만듦) ---
variable "create_network" {
  description = "true 면 network.tf 가 VCN+IG+RT+SL+Subnet 새로 생성. false 면 var.subnet_ocid 필수."
  type        = bool
  default     = false
}
variable "subnet_ocid" {
  description = "create_network=false 일 때 LB 가 들어갈 기존 subnet OCID"
  type        = string
  default     = ""
}
variable "network_name_prefix" {
  type    = string
  default = "ords"
}
variable "vcn_cidr" {
  type    = string
  default = "10.99.0.0/16"
}
variable "public_subnet_cidr" {
  type    = string
  default = "10.99.1.0/24"
}
variable "ssh_ingress_cidr" {
  description = "SSH(22) 허용 source CIDR. PoC: 0.0.0.0/0. 운영은 회사망/Bastion IP 로 좁힐 것."
  type        = string
  default     = "0.0.0.0/0"
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
