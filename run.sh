#!/usr/bin/env bash
# ============================================================
# run.sh  —  ORDS install cookbook 단일 진입점
#
# Usage:
#   ./run.sh prereq | install | configure | start | smoke
#   ./run.sh ha | ha-tf {plan|apply|destroy|output}
#   ./run.sh fetch-cert     # OCI Cert Service → OS 로 cert PEM 내려받아 등록
#   ./run.sh vector-demo {all|admin|credential|schema|publish|test|onnx|cleanup}
#                           # ADB 위에 OCI GenAI Cohere v3/v4 임베딩 + ORDS vector 검색 모듈 발행
#   ./run.sh all       (= prereq install configure start smoke)
#   ./run.sh teardown
# ============================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_ROOT"

# .env 없으면 example 복사 + 안내 후 종료
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo ".env 가 없어서 .env.example 복사함. 값 채운 뒤 다시 실행하세요:"
  echo "  vi .env && ./run.sh ${1:-all}"
  exit 1
fi

# shellcheck disable=SC1091
source ./.env
source ./scripts/lib/common.sh
init_logging

cmd="${1:-all}"; shift || true

# DB 비밀번호는 실제로 필요한 커맨드일 때만 프롬프트
case "$cmd" in
  configure|smoke|all)
    [[ -z "${ADMIN_PASSWORD:-}" ]] && {
      read -rsp "ADB ADMIN_PASSWORD: " ADMIN_PASSWORD; echo
      export ADMIN_PASSWORD
    }
    [[ -z "${ORDS_DB_USER_PASSWORD:-}" ]] && {
      read -rsp "ORDS_DB_USER_PASSWORD (런타임 계정): " ORDS_DB_USER_PASSWORD; echo
      export ORDS_DB_USER_PASSWORD
    }
    [[ -z "${ORDS_GATEWAY_USER_PASSWORD:-}" ]] && {
      read -rsp "ORDS_GATEWAY_USER_PASSWORD (PL/SQL gateway): " ORDS_GATEWAY_USER_PASSWORD; echo
      export ORDS_GATEWAY_USER_PASSWORD
    }
    ;;
  vector-demo)
    [[ -z "${ADMIN_PASSWORD:-}" ]] && {
      read -rsp "ADB ADMIN_PASSWORD: " ADMIN_PASSWORD; echo
      export ADMIN_PASSWORD
    }
    [[ -z "${VECTOR_DEMO_PASSWORD:-}" ]] && {
      read -rsp "VECTOR_DEMO_PASSWORD (데모 스키마용): " VECTOR_DEMO_PASSWORD; echo
      export VECTOR_DEMO_PASSWORD
    }
    ;;
esac

case "$cmd" in
  prereq)    bash scripts/00_prereq.sh ;;
  install)   bash scripts/01_install.sh ;;
  configure) bash scripts/02_configure.sh ;;
  start)     bash scripts/03_start.sh ;;
  smoke)     bash scripts/04_smoke.sh ;;
  ha)        bash scripts/05_ha.sh ;;
  ha-tf)     bash scripts/06_lb_terraform.sh "$@" ;;
  fetch-cert) bash scripts/07_fetch_oci_cert.sh ;;
  vector-demo) bash scripts/08_vector_demo.sh "$@" ;;
  teardown)  bash scripts/99_teardown.sh ;;
  all)
    bash scripts/00_prereq.sh
    bash scripts/01_install.sh
    bash scripts/02_configure.sh
    bash scripts/03_start.sh
    bash scripts/04_smoke.sh
    ok "전체 설치 완료"
    ;;
  *)
    err "unknown command: $cmd"
    sed -n '5,12p' "$0" >&2
    exit 1
    ;;
esac
