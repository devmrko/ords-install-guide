#!/usr/bin/env bash
# ============================================================
# 06_lb_terraform.sh
# - .env 값을 TF_VAR_* 로 export
# - 사설 인증서 PEM 들을 그대로 main.tf 가 oci_certificates_management_certificate
#   리소스로 import 함
# - usage: ./run.sh ha-tf {plan|apply|destroy|output}
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

need_cmd terraform

require_env OCI_COMPARTMENT_OCID OCI_VCN_OCID OCI_LB_SUBNET_OCID \
            HA_NODES ORDS_PORT LB_HEALTHCHECK_PATH \
            LB_SHAPE LB_BANDWIDTH_MIN LB_BANDWIDTH_MAX LB_IS_PRIVATE

# 인증서: OCI_CERT_OCID 가 있으면 그거 사용, 없으면 PEM 들로 새로 import
if [[ -n "${OCI_CERT_OCID:-}" ]]; then
  log "기존 OCI Cert OCID 사용: $OCI_CERT_OCID"
  export TF_VAR_cert_ocid="$OCI_CERT_OCID"
  export TF_VAR_import_cert=false
else
  require_env TLS_CERT_PEM TLS_KEY_PEM OCI_CERT_NAME
  [[ -f "$TLS_CERT_PEM" ]] || die "TLS_CERT_PEM 없음: $TLS_CERT_PEM"
  [[ -f "$TLS_KEY_PEM"  ]] || die "TLS_KEY_PEM  없음: $TLS_KEY_PEM"
  log "사설 인증서 import: $OCI_CERT_NAME"
  export TF_VAR_import_cert=true
  export TF_VAR_cert_name="$OCI_CERT_NAME"
  export TF_VAR_cert_pem="$(cat "$TLS_CERT_PEM")"
  export TF_VAR_key_pem="$(cat "$TLS_KEY_PEM")"
  export TF_VAR_chain_pem="$(cat "${TLS_CHAIN_PEM:-/dev/null}" 2>/dev/null || true)"
fi

export TF_VAR_compartment_ocid="$OCI_COMPARTMENT_OCID"
export TF_VAR_vcn_ocid="$OCI_VCN_OCID"
export TF_VAR_subnet_ocid="$OCI_LB_SUBNET_OCID"
export TF_VAR_ords_nodes="$HA_NODES"
export TF_VAR_ords_port="$ORDS_PORT"
export TF_VAR_healthcheck_path="$LB_HEALTHCHECK_PATH"
export TF_VAR_lb_shape="$LB_SHAPE"
export TF_VAR_lb_bw_min="$LB_BANDWIDTH_MIN"
export TF_VAR_lb_bw_max="$LB_BANDWIDTH_MAX"
export TF_VAR_lb_is_private="$LB_IS_PRIVATE"

cd "$REPO_ROOT/terraform"

cmd="${1:-apply}"
case "$cmd" in
  plan)    terraform init -upgrade && terraform plan ;;
  apply)   terraform init -upgrade && terraform apply -auto-approve ;;
  destroy) terraform destroy -auto-approve ;;
  output)  terraform output ;;
  *) die "usage: $0 {plan|apply|destroy|output}";;
esac
