#!/usr/bin/env bash
# ============================================================
# 08_vector_demo.sh
#
# 기존에 설치된 ORDS + ADB 위에 다음을 한 번에 셋업:
#   - VECTOR_DEMO 사용자 / DOC_CHUNKS 테이블 (embedding_v3 + embedding_v4)
#   - 서버측 임베딩: OCI GenAI Cohere
#       * embedding_v3 : cohere.embed-multilingual-v3.0 (1024-dim)
#       * embedding_v4 : cohere.embed-v4.0              (1024-dim 기본)
#   - ORDS 모듈 vector.search (POST /docs/search, GET /docs/, GET /docs/list)
#
# 멱등성: 각 SQL 스크립트가 존재 여부 확인 후 skip 처리
#
# Usage:
#   ./run.sh vector-demo            # 풀 셋업 (01 → 06)
#   ./run.sh vector-demo admin      # 사용자 + ACL + ORDS schema enable 만
#   ./run.sh vector-demo schema     # 03 → 06 만
#   ./run.sh vector-demo publish    # ORDS 모듈만 재발행
#   ./run.sh vector-demo test       # 06 만 (검증)
#   ./run.sh vector-demo onnx       # (선택) optional_load_onnx.sql 로 ONNX 모델 로드
#   ./run.sh vector-demo cleanup    # 99_cleanup
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ADB_TNS WALLET_PATH \
            ADMIN_USER ADMIN_PASSWORD \
            VECTOR_DEMO_USER VECTOR_DEMO_PASSWORD \
            OCI_GENAI_CREDENTIAL OCI_GENAI_ENDPOINT \
            OCI_GENAI_MODEL_V3 OCI_GENAI_MODEL_V4

# ONNX 경로 (optional) — 'onnx' 서브명령 사용 시에만 필요
: "${VECTOR_MODEL_NAME:=DOC_MODEL}"
: "${VECTOR_MODEL_URI:=}"
: "${VECTOR_MODEL_FILE:=}"

export TNS_ADMIN="$WALLET_PATH"
SQLCL="${SQLCL:-/opt/oracle/sqlcl/bin/sql}"
[[ -x "$SQLCL" ]] || die "sqlcl 없음: $SQLCL (01_install.sh 먼저 실행)"

SQLDIR="$REPO_ROOT/sql/vector"

# DEFINE 값을 안전하게 한 줄로 만들기
_def() {
  printf "define %s=%s\n" "$1" "$2"
}

run_as_admin() {
  local script="$1"
  log "ADMIN: $script"
  "$SQLCL" -S /nolog <<SQL
$(_def VECTOR_DEMO_USER     "$VECTOR_DEMO_USER")
$(_def VECTOR_DEMO_PASSWORD "$VECTOR_DEMO_PASSWORD")
$(_def VECTOR_MODEL_NAME    "$VECTOR_MODEL_NAME")
$(_def VECTOR_MODEL_URI     "$VECTOR_MODEL_URI")
$(_def VECTOR_MODEL_FILE    "$VECTOR_MODEL_FILE")
$(_def OCI_GENAI_CREDENTIAL "$OCI_GENAI_CREDENTIAL")
$(_def OCI_GENAI_ENDPOINT   "$OCI_GENAI_ENDPOINT")
$(_def OCI_GENAI_MODEL_V3   "$OCI_GENAI_MODEL_V3")
$(_def OCI_GENAI_MODEL_V4   "$OCI_GENAI_MODEL_V4")
connect $ADMIN_USER/"$ADMIN_PASSWORD"@$ADB_TNS
@$SQLDIR/$script
SQL
}

run_as_demo() {
  local script="$1"
  log "$VECTOR_DEMO_USER: $script"
  "$SQLCL" -S /nolog <<SQL
$(_def VECTOR_DEMO_USER     "$VECTOR_DEMO_USER")
$(_def VECTOR_MODEL_NAME    "$VECTOR_MODEL_NAME")
$(_def OCI_GENAI_CREDENTIAL "$OCI_GENAI_CREDENTIAL")
$(_def OCI_GENAI_ENDPOINT   "$OCI_GENAI_ENDPOINT")
$(_def OCI_GENAI_MODEL_V3   "$OCI_GENAI_MODEL_V3")
$(_def OCI_GENAI_MODEL_V4   "$OCI_GENAI_MODEL_V4")
connect $VECTOR_DEMO_USER/"$VECTOR_DEMO_PASSWORD"@$ADB_TNS
@$SQLDIR/$script
SQL
}

step="${1:-all}"

case "$step" in
  all)
    run_as_admin 01_admin_setup.sql
    run_as_demo  03_schema.sql
    run_as_demo  04_seed.sql
    run_as_demo  05_ords_publish.sql
    run_as_demo  06_test.sql
    ok "vector 데모 셋업 완료"
    echo
    echo "▶ 다음 curl 로 동작 확인:"
    echo
    echo "  # Cohere embed v4 (기본)"
    echo "  curl -sS -X POST http://localhost:${ORDS_PORT:-8080}/ords/vector/docs/search \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"q\": \"database REST API\", \"k\": 3, \"by\": \"v4\"}' | jq ."
    echo
    echo "  # Cohere embed multilingual v3 (한국어 등 다국어 쿼리)"
    echo "  curl -sS -X POST http://localhost:${ORDS_PORT:-8080}/ords/vector/docs/search \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"q\": \"지하철 노선\", \"k\": 3, \"by\": \"v3\"}' | jq ."
    echo
    echo "  curl -sS http://localhost:${ORDS_PORT:-8080}/ords/vector/docs/list | jq ."
    echo
    ;;
  admin)   run_as_admin 01_admin_setup.sql ;;
  onnx)
    [[ -n "$VECTOR_MODEL_URI" && -n "$VECTOR_MODEL_FILE" ]] \
      || die "VECTOR_MODEL_URI / VECTOR_MODEL_FILE 미설정 (optional ONNX 로드용)"
    run_as_admin optional_load_onnx.sql
    ;;
  schema)
    run_as_demo 03_schema.sql
    run_as_demo 04_seed.sql
    run_as_demo 05_ords_publish.sql
    run_as_demo 06_test.sql
    ;;
  publish) run_as_demo  05_ords_publish.sql ;;
  test)    run_as_demo  06_test.sql ;;
  cleanup) run_as_admin 99_cleanup.sql ;;
  *)
    die "usage: $0 {all|admin|schema|publish|test|onnx|cleanup}"
    ;;
esac
