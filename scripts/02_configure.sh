#!/usr/bin/env bash
# ============================================================
# 02_configure.sh
# - wallet 위치/권한 확인
# - ords install (--silent) 로 default pool 생성 + ADB 연결
# - ORDS_PUBLIC_USER 등 자동 생성
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ORDS_HOME ORDS_CONFIG ADB_TNS WALLET_PATH \
            ADMIN_USER ADMIN_PASSWORD ORDS_PUBLIC_USER_PASSWORD \
            POOL_NAME JDBC_INITIAL_LIMIT JDBC_MAX_LIMIT

[[ -d "$WALLET_PATH" ]] || die "WALLET_PATH 없음: $WALLET_PATH (ADB 콘솔에서 wallet 받아 풀어두세요)"
[[ -f "$WALLET_PATH/tnsnames.ora" ]] || die "wallet 디렉토리에 tnsnames.ora 없음"
grep -q "^${ADB_TNS%[_,]*}" "$WALLET_PATH/tnsnames.ora" 2>/dev/null \
  || warn "tnsnames.ora 에 ${ADB_TNS} alias 가 안 보임 — 확인 권장"

# TNS_ADMIN 지정해서 wallet 위치 알려주기
export TNS_ADMIN="$WALLET_PATH"

# 이미 pool이 있으면 skip
if as_root test -f "$ORDS_CONFIG/databases/$POOL_NAME/pool.xml"; then
  ok "pool '$POOL_NAME' 이미 구성됨 — skip"
  exit 0
fi

log "ords install 실행 (silent)"
as_root -E "$ORDS_HOME/bin/ords" \
  --config "$ORDS_CONFIG" \
  install \
  --admin-user "$ADMIN_USER" \
  --db-pool "$POOL_NAME" \
  --feature-db-api true \
  --feature-rest-enabled-sql true \
  --log-folder "$ORDS_CONFIG/logs" \
  --db-wallet-zip-path "$WALLET_PATH" \
  --db-tns-alias "$ADB_TNS" \
  --jdbc-init-limit "$JDBC_INITIAL_LIMIT" \
  --jdbc-max-limit "$JDBC_MAX_LIMIT" \
  --password-stdin <<EOF
$ADMIN_PASSWORD
$ORDS_PUBLIC_USER_PASSWORD
EOF

ok "configure 완료 — config: $ORDS_CONFIG"
