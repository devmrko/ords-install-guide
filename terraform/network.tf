# ============================================================
# network.tf  (OPTIONAL — toggle via var.create_network)
# - var.create_network=true  → 신규 VCN + IG + RT + SL + Public Subnet 생성
#                              ORDS 노드는 이 subnet 안에 띄우면 됨 (compute 는 본 cookbook 범위 밖)
# - var.create_network=false → var.subnet_ocid (이미 있는 subnet) 그대로 사용
#
# LB 도 ORDS 노드도 같은 subnet 에 두는 단순 구성. 운영은 LB 용 public subnet 과
# ORDS 용 private subnet 을 분리 권장 (docs/04-ha.md §4.2).
# ============================================================

resource "oci_core_vcn" "ords" {
  count          = var.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  display_name   = var.network_name_prefix
  cidr_blocks    = [var.vcn_cidr]
  dns_label      = replace(var.network_name_prefix, "-", "")
}

resource "oci_core_internet_gateway" "ig" {
  count          = var.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ords[0].id
  display_name   = "${var.network_name_prefix}-ig"
  enabled        = true
}

resource "oci_core_route_table" "public_rt" {
  count          = var.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ords[0].id
  display_name   = "${var.network_name_prefix}-rt-public"

  route_rules {
    network_entity_id = oci_core_internet_gateway.ig[0].id
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
  }
}

resource "oci_core_security_list" "ords_sl" {
  count          = var.create_network ? 1 : 0
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.ords[0].id
  display_name   = "${var.network_name_prefix}-sl"

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  # SSH (PoC: 0.0.0.0/0. 운영은 var.ssh_ingress_cidr 좁히기)
  ingress_security_rules {
    source   = var.ssh_ingress_cidr
    protocol = "6"
    tcp_options {
      min = 22
      max = 22
    }
  }

  # LB → 인터넷 (443/80)
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 443
      max = 443
    }
  }
  ingress_security_rules {
    source   = "0.0.0.0/0"
    protocol = "6"
    tcp_options {
      min = 80
      max = 80
    }
  }

  # LB → ORDS backends (VCN 내부에서 8080)
  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = "6"
    tcp_options {
      min = var.ords_port
      max = var.ords_port
    }
  }

  # ICMP (path MTU 등 정상화)
  ingress_security_rules {
    source   = var.vcn_cidr
    protocol = "1"
  }
}

resource "oci_core_subnet" "public" {
  count                      = var.create_network ? 1 : 0
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.ords[0].id
  display_name               = "${var.network_name_prefix}-subnet-public"
  cidr_block                 = var.public_subnet_cidr
  route_table_id             = oci_core_route_table.public_rt[0].id
  security_list_ids          = [oci_core_security_list.ords_sl[0].id]
  prohibit_public_ip_on_vnic = false
  dns_label                  = "public"
}

# main.tf 의 LB 가 참조할 effective subnet OCID
locals {
  effective_subnet_ocid = var.create_network ? oci_core_subnet.public[0].id : var.subnet_ocid
}
