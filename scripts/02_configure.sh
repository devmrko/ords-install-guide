#!/usr/bin/env bash
# ============================================================
# 02_configure.sh
# - wallet zip 준비 (없으면 WALLET_PATH 디렉토리를 zip 으로 묶음)
# - ords install adb (--silent) 로 default pool 생성 + ADB 연결
# - ORDS_DB_USER, ORDS_GATEWAY_USER 두 계정 생성
#
# ORDS 24.x CLI 기준 (https://docs.oracle.com/.../ordig/installing-and-configuring-customer-managed-ords-autonomous-database.html)
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ORDS_HOME ORDS_CONFIG ADB_TNS WALLET_PATH \
            ADMIN_USER ADMIN_PASSWORD \
            ORDS_DB_USER ORDS_DB_USER_PASSWORD \
            ORDS_GATEWAY_USER ORDS_GATEWAY_USER_PASSWORD \
            POOL_NAME

[[ -d "$WALLET_PATH" ]] || die "WALLET_PATH 없음: $WALLET_PATH (ADB 콘솔에서 wallet 받아 풀어두세요)"
[[ -f "$WALLET_PATH/tnsnames.ora" ]] || die "wallet 디렉토리에 tnsnames.ora 없음"

# --wallet 인자는 zip 파일 필요. 없으면 자동 생성.
if [[ -z "${WALLET_ZIP:-}" ]] || [[ ! -f "$WALLET_ZIP" ]]; then
  WALLET_ZIP="${WALLET_ZIP:-/opt/oracle/wallet.zip}"
  need_cmd zip
  log "wallet zip 생성: $WALLET_ZIP"
  ( cd "$WALLET_PATH" && as_root zip -q -r "$WALLET_ZIP" . )
  as_root chown "${ORDS_USER}:${ORDS_GROUP}" "$WALLET_ZIP"
  as_root chmod 600 "$WALLET_ZIP"
fi

# TNS_ADMIN 지정 (sqlcl/sqlplus 가 후속 단계에서 wallet 인식)
export TNS_ADMIN="$WALLET_PATH"

# 이미 pool이 있으면 skip (멱등성)
if as_root test -f "$ORDS_CONFIG/databases/$POOL_NAME/pool.xml"; then
  ok "pool '$POOL_NAME' 이미 구성됨 — skip"
  exit 0
fi

log "ords install adb 실행 (silent)"
# 비밀번호는 3개 순서: admin → db_user → gateway_user
as_root -E "$ORDS_HOME/bin/ords" \
  --config "$ORDS_CONFIG" \
  install adb \
  --admin-user "$ADMIN_USER" \
  --db-user "$ORDS_DB_USER" \
  --gateway-user "$ORDS_GATEWAY_USER" \
  --db-pool "$POOL_NAME" \
  --wallet "$WALLET_ZIP" \
  --wallet-service-name "$ADB_TNS" \
  --feature-sdw true \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --jdbc-init-limit "${JDBC_INITIAL_LIMIT:-5}" \
  --jdbc-max-limit  "${JDBC_MAX_LIMIT:-25}" \
  --log-folder "$ORDS_CONFIG/logs" \
  --password-stdin <<EOF
$ADMIN_PASSWORD
$ORDS_DB_USER_PASSWORD
$ORDS_GATEWAY_USER_PASSWORD
EOF

ok "configure 완료 — config: $ORDS_CONFIG"
