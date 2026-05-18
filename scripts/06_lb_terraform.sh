#!/usr/bin/env bash
# ============================================================
# 06_lb_terraform.sh
# - PEM 본문을 환경변수로 export 하지 않고 임시 tfvars 파일(600)로 전달
#   (ps e / /proc/*/environ 노출 방지)
# - 일반 인자 값들만 TF_VAR_* 사용
# - usage: ./run.sh ha-tf {plan|apply|destroy|output} [추가 인자]
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

need_cmd terraform

require_env OCI_COMPARTMENT_OCID OCI_LB_SUBNET_OCID \
            HA_NODES ORDS_PORT LB_HEALTHCHECK_PATH \
            LB_SHAPE LB_BANDWIDTH_MIN LB_BANDWIDTH_MAX LB_IS_PRIVATE

# 일반 (sensitive 아닌) 변수는 환경변수로 OK
export TF_VAR_compartment_ocid="$OCI_COMPARTMENT_OCID"
export TF_VAR_subnet_ocid="$OCI_LB_SUBNET_OCID"
export TF_VAR_ords_nodes="$HA_NODES"
export TF_VAR_ords_port="$ORDS_PORT"
export TF_VAR_healthcheck_path="$LB_HEALTHCHECK_PATH"
export TF_VAR_lb_shape="$LB_SHAPE"
export TF_VAR_lb_bw_min="$LB_BANDWIDTH_MIN"
export TF_VAR_lb_bw_max="$LB_BANDWIDTH_MAX"
export TF_VAR_lb_is_private="$LB_IS_PRIVATE"

# 인증서 PEM 은 환경변수 대신 임시 tfvars 파일(600) 로 전달
SECRETS_TF=""
cleanup() { [[ -n "$SECRETS_TF" && -f "$SECRETS_TF" ]] && shred -u "$SECRETS_TF" 2>/dev/null || rm -f "$SECRETS_TF"; }
trap cleanup EXIT INT TERM

if [[ -n "${OCI_CERT_OCID:-}" ]]; then
  log "기존 OCI Cert OCID 사용: $OCI_CERT_OCID"
  export TF_VAR_import_cert=false
  export TF_VAR_cert_ocid="$OCI_CERT_OCID"
else
  require_env TLS_CERT_PEM TLS_KEY_PEM OCI_CERT_NAME
  [[ -f "$TLS_CERT_PEM" ]] || die "TLS_CERT_PEM 없음: $TLS_CERT_PEM"
  [[ -f "$TLS_KEY_PEM"  ]] || die "TLS_KEY_PEM  없음: $TLS_KEY_PEM"
  log "사설 인증서 import: $OCI_CERT_NAME (tfvars 파일 권한 600 으로 주입)"

  SECRETS_TF="$REPO_ROOT/terraform/.secrets.auto.tfvars"
  umask 077
  : > "$SECRETS_TF"
  chmod 600 "$SECRETS_TF"
  {
    echo "import_cert = true"
    printf 'cert_name = %s\n' "$(printf '%s' "$OCI_CERT_NAME" | sed 's/"/\\"/g; s/.*/"&"/')"
    printf 'cert_pem  = <<__EOT_CERT__\n%s\n__EOT_CERT__\n' "$(cat "$TLS_CERT_PEM")"
    printf 'key_pem   = <<__EOT_KEY__\n%s\n__EOT_KEY__\n'  "$(cat "$TLS_KEY_PEM")"
    if [[ -n "${TLS_CHAIN_PEM:-}" && -f "$TLS_CHAIN_PEM" ]]; then
      printf 'chain_pem = <<__EOT_CHAIN__\n%s\n__EOT_CHAIN__\n' "$(cat "$TLS_CHAIN_PEM")"
    fi
  } > "$SECRETS_TF"
fi

cd "$REPO_ROOT/terraform"

cmd="${1:-apply}"; shift || true

# init 은 첫 회 또는 명시적으로만. -upgrade 는 재현성 해치므로 옵션화.
if [[ ! -d .terraform ]]; then
  terraform init
fi

case "$cmd" in
  plan)    terraform plan    "$@" ;;
  apply)   terraform apply -auto-approve "$@" ;;
  destroy) terraform destroy -auto-approve "$@" ;;
  output)  terraform output  "$@" ;;
  upgrade) terraform init -upgrade ;;            # 의도적인 provider 업그레이드
  *) die "usage: $0 {plan|apply|destroy|output|upgrade} [extra-args]";;
esac
