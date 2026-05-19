#!/usr/bin/env bash
# ============================================================
# 08_vector_demo.sh
#
# 기존에 설치된 ORDS + ADB 위에 다음을 한 번에 셋업:
#   - VECTOR_DEMO 사용자 / DOC_CHUNKS 테이블 (embedding 단일 컬럼)
#   - OCI GenAI inference host 로 outbound network ACL 부여
#   - DBMS_VECTOR_CHAIN.CREATE_CREDENTIAL 로 OCI native API key 등록
#   - 임베딩: DBMS_VECTOR.UTL_TO_EMBEDDING(provider=ocigenai) → OCI GenAI Cohere
#       * embedding : cohere.embed-v4.0 (default 1536-dim)
#   - ORDS 모듈 vector.search (POST /docs/search, GET /docs/, GET /docs/list)
#
# 멱등성: 각 SQL 스크립트가 존재 여부 확인 후 skip 처리
#
# Usage:
#   ./run.sh vector-demo              # 풀 셋업 (01 → 06)
#   ./run.sh vector-demo admin        # 사용자 + ACL + ORDS schema enable
#   ./run.sh vector-demo credential   # 02_credential.sql 만 (PEM 갱신 시)
#   ./run.sh vector-demo schema       # 03 → 06
#   ./run.sh vector-demo publish      # ORDS 모듈만 재발행
#   ./run.sh vector-demo test         # 06 만 (검증)
#   ./run.sh vector-demo onnx         # (선택) optional_load_onnx.sql
#   ./run.sh vector-demo cleanup      # 99_cleanup
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ADB_TNS WALLET_PATH \
            ADMIN_USER ADMIN_PASSWORD \
            VECTOR_DEMO_USER VECTOR_DEMO_PASSWORD \
            OCI_REGION OCI_COMPARTMENT_OCID \
            OCI_GENAI_CRED_NAME OCI_GENAI_MODEL OCI_GENAI_DIM \
            OCI_GENAI_URL OCI_GENAI_HOST \
            OCI_USER_OCID OCI_TENANCY_OCID \
            OCI_KEY_FINGERPRINT OCI_API_KEY_PEM

[[ -r "$OCI_API_KEY_PEM" ]] || die "OCI API key PEM 읽기 실패: $OCI_API_KEY_PEM"

# ONNX 경로 (optional) — 'onnx' 서브명령 사용 시에만 필요
: "${VECTOR_MODEL_NAME:=DOC_MODEL}"
: "${VECTOR_MODEL_URI:=}"
: "${VECTOR_MODEL_FILE:=}"

export TNS_ADMIN="$WALLET_PATH"
SQLCL="${SQLCL:-/opt/oracle/sqlcl/bin/sql}"
[[ -x "$SQLCL" ]] || die "sqlcl 없음: $SQLCL (01_install.sh 먼저 실행)"

SQLDIR="$REPO_ROOT/sql/vector"

# PEM → BEGIN/END/whitespace 제거한 base64 본문 1줄
strip_pem() {
  # PKCS#8 (-----BEGIN PRIVATE KEY-----) 와 PKCS#1 (-----BEGIN RSA PRIVATE KEY-----) 모두 처리
  awk 'BEGIN{p=0} /-----BEGIN/{p=1; next} /-----END/{p=0} p {printf "%s", $0}' "$OCI_API_KEY_PEM"
}

OCI_PRIVATE_KEY="$(strip_pem)"
[[ -n "$OCI_PRIVATE_KEY" ]] || die "PEM 본문 추출 실패: $OCI_API_KEY_PEM"

# DEFINE 한 줄 만들기 헬퍼
_def() { printf "define %s=%s\n" "$1" "$2"; }

run_as_admin() {
  local script="$1"
  log "ADMIN: $script"
  "$SQLCL" -S /nolog <<SQL
$(_def VECTOR_DEMO_USER     "$VECTOR_DEMO_USER")
$(_def VECTOR_DEMO_PASSWORD "$VECTOR_DEMO_PASSWORD")
$(_def OCI_GENAI_HOST       "$OCI_GENAI_HOST")
$(_def VECTOR_MODEL_NAME    "$VECTOR_MODEL_NAME")
$(_def VECTOR_MODEL_URI     "$VECTOR_MODEL_URI")
$(_def VECTOR_MODEL_FILE    "$VECTOR_MODEL_FILE")
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
$(_def OCI_GENAI_CRED_NAME  "$OCI_GENAI_CRED_NAME")
$(_def OCI_GENAI_URL        "$OCI_GENAI_URL")
$(_def OCI_GENAI_MODEL      "$OCI_GENAI_MODEL")
$(_def OCI_GENAI_DIM        "$OCI_GENAI_DIM")
connect $VECTOR_DEMO_USER/"$VECTOR_DEMO_PASSWORD"@$ADB_TNS
@$SQLDIR/$script
SQL
}

# credential 단계는 long PEM 본문을 DEFINE 으로 전달해야 해서 별도 처리
run_credential() {
  log "$VECTOR_DEMO_USER: 02_credential.sql"
  "$SQLCL" -S /nolog <<SQL
$(_def VECTOR_DEMO_USER      "$VECTOR_DEMO_USER")
$(_def OCI_GENAI_CRED_NAME   "$OCI_GENAI_CRED_NAME")
$(_def OCI_USER_OCID         "$OCI_USER_OCID")
$(_def OCI_TENANCY_OCID      "$OCI_TENANCY_OCID")
$(_def OCI_COMPARTMENT_OCID  "$OCI_COMPARTMENT_OCID")
$(_def OCI_KEY_FINGERPRINT   "$OCI_KEY_FINGERPRINT")
$(_def OCI_PRIVATE_KEY       "$OCI_PRIVATE_KEY")
connect $VECTOR_DEMO_USER/"$VECTOR_DEMO_PASSWORD"@$ADB_TNS
@$SQLDIR/02_credential.sql
SQL
}

step="${1:-all}"

case "$step" in
  all)
    run_as_admin 01_admin_setup.sql
    run_credential
    run_as_demo  03_schema.sql
    run_as_demo  04_seed.sql
    run_as_demo  05_ords_publish.sql
    run_as_demo  06_test.sql
    ok "vector 데모 셋업 완료"
    echo
    echo "▶ 다음 curl 로 동작 확인 (Cohere embed v4 via OCI GenAI):"
    echo
    echo "  curl -sS -X POST http://localhost:${ORDS_PORT:-8080}/ords/vector/docs/search \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"q\": \"database REST API\", \"k\": 3}' | jq ."
    echo
    echo "  # 한국어 쿼리 (cohere.embed-v4.0 은 multilingual)"
    echo "  curl -sS -X POST http://localhost:${ORDS_PORT:-8080}/ords/vector/docs/search \\"
    echo "       -H 'Content-Type: application/json' \\"
    echo "       -d '{\"q\": \"지하철 노선\", \"k\": 3}' | jq ."
    echo
    echo "  curl -sS http://localhost:${ORDS_PORT:-8080}/ords/vector/docs/list | jq ."
    echo
    ;;
  admin)      run_as_admin 01_admin_setup.sql ;;
  credential) run_credential ;;
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
    die "usage: $0 {all|admin|credential|schema|publish|test|onnx|cleanup}"
    ;;
esac
