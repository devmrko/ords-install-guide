#!/usr/bin/env bash
# ============================================================
# 07_fetch_oci_cert.sh
# - OCI Certificate Service 에 등록된 cert 를 OCI CLI 로 받아서
#   OS 의 지정 경로에 PEM 파일들로 떨어뜨림
# - 옵션 1: OS truststore 에 등록 (curl/openssl/java 등이 신뢰)
# - 옵션 2: ORDS 가 직접 HTTPS 종단할 때 사용할 경로로 배치
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

need_cmd oci jq

require_env OCI_CERT_OCID
[[ -z "${TLS_CERT_PEM:-}"  ]] && TLS_CERT_PEM=/etc/ords/tls/cert.pem
[[ -z "${TLS_KEY_PEM:-}"   ]] && TLS_KEY_PEM=/etc/ords/tls/privkey.pem
[[ -z "${TLS_CHAIN_PEM:-}" ]] && TLS_CHAIN_PEM=/etc/ords/tls/chain.pem

OUT_DIR=$(dirname "$TLS_CERT_PEM")
as_root mkdir -p "$OUT_DIR"

log "1/4 OCI 에서 cert bundle 가져오기"
# CERTIFICATE_CONTENT_WITH_PRIVATE_KEY = cert + key + chain
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

oci certificates certificate-bundle get \
  --certificate-id "$OCI_CERT_OCID" \
  --bundle-type CERTIFICATE_CONTENT_WITH_PRIVATE_KEY \
  --output json > "$TMP"

CERT=$(jq -r '.data."certificate-pem" // empty'    "$TMP")
KEY=$( jq -r '.data."private-key-pem" // empty'    "$TMP")
CHAIN=$(jq -r '.data."cert-chain-pem" // empty'    "$TMP")
VERSION=$(jq -r '.data."version-number" // "?"'     "$TMP")
SERIAL=$( jq -r '.data."serial-number" // "?"'      "$TMP")

[[ -z "$CERT" ]] && die "cert PEM 비어있음 — OCI 권한 확인 (CERTIFICATE_CONTENT_WITH_PRIVATE_KEY 읽기)"
[[ -z "$KEY"  ]] && warn "private-key-pem 이 비어있음. OCI Cert Service 에서 관리하는 키는 export 불가일 수 있음."

log "2/4 PEM 파일 쓰기"
printf '%s' "$CERT"  | as_root tee "$TLS_CERT_PEM"  >/dev/null
[[ -n "$KEY" ]]   && printf '%s' "$KEY"   | as_root tee "$TLS_KEY_PEM"   >/dev/null
[[ -n "$CHAIN" ]] && printf '%s' "$CHAIN" | as_root tee "$TLS_CHAIN_PEM" >/dev/null

as_root chmod 644 "$TLS_CERT_PEM" "${TLS_CHAIN_PEM:-/dev/null}" 2>/dev/null || true
[[ -f "$TLS_KEY_PEM" ]] && as_root chmod 600 "$TLS_KEY_PEM"
as_root chown "${ORDS_USER}:${ORDS_GROUP}" "$TLS_CERT_PEM" "$TLS_KEY_PEM" "$TLS_CHAIN_PEM" 2>/dev/null || true

ok "  cert : $TLS_CERT_PEM  (version=$VERSION serial=$SERIAL)"
[[ -f "$TLS_KEY_PEM"   ]] && ok "  key  : $TLS_KEY_PEM"
[[ -f "$TLS_CHAIN_PEM" ]] && ok "  chain: $TLS_CHAIN_PEM"

log "3/4 OS truststore 등록 (chain 을 시스템 CA 로 신뢰)"
if [[ -f "$TLS_CHAIN_PEM" ]]; then
  if [[ -d /etc/pki/ca-trust/source/anchors ]]; then
    # RHEL / OL
    as_root cp "$TLS_CHAIN_PEM" /etc/pki/ca-trust/source/anchors/ords-oci-chain.pem
    as_root update-ca-trust extract
    ok "  RHEL/OL truststore 갱신"
  elif [[ -d /usr/local/share/ca-certificates ]]; then
    # Ubuntu / Debian
    as_root cp "$TLS_CHAIN_PEM" /usr/local/share/ca-certificates/ords-oci-chain.crt
    as_root update-ca-certificates
    ok "  Ubuntu/Debian truststore 갱신"
  else
    warn "  알 수 없는 배포판 — 수동으로 chain 을 OS truststore 에 등록 필요"
  fi
else
  warn "  chain PEM 없음 — truststore 등록 skip"
fi

log "4/4 Java truststore (JDK cacerts) 등록 — ORDS 가 OCI cert 를 신뢰하도록"
if [[ -n "${JAVA_HOME:-}" && -f "$JAVA_HOME/lib/security/cacerts" && -f "$TLS_CHAIN_PEM" ]]; then
  ALIAS="ords-oci-chain"
  # 이미 있으면 갱신
  as_root "$JAVA_HOME/bin/keytool" -delete -alias "$ALIAS" \
    -keystore "$JAVA_HOME/lib/security/cacerts" -storepass changeit 2>/dev/null || true
  as_root "$JAVA_HOME/bin/keytool" -import -trustcacerts -noprompt \
    -alias "$ALIAS" \
    -file "$TLS_CHAIN_PEM" \
    -keystore "$JAVA_HOME/lib/security/cacerts" \
    -storepass changeit
  ok "  Java cacerts 에 등록 (alias=$ALIAS)"
fi

ok "fetch 완료. 갱신은 OCI 에서 cert version 올라가면 이 스크립트 재실행만 하면 됨."
