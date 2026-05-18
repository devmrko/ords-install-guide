#!/usr/bin/env bash
# ============================================================
# 04_smoke.sh
# - HTTP landing endpoint 호출
# - sqlcl 로 sql/smoke_test.sql 실행
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ORDS_PORT ADB_TNS ADMIN_USER ADMIN_PASSWORD WALLET_PATH

export TNS_ADMIN="$WALLET_PATH"
SQLCL=/opt/oracle/sqlcl/bin/sql
[[ -x "$SQLCL" ]] || die "sqlcl 없음 — 01_install.sh 먼저"

log "1/2 HTTP landing"
URL="http://localhost:${ORDS_PORT}/ords/_/landing"
if curl -fsS "$URL" >/dev/null; then
  ok "landing OK: $URL"
else
  warn "landing 실패: $URL — 5초 후 1회 재시도"
  sleep 5
  curl -fsS "$URL" >/dev/null && ok "landing OK (재시도)" || die "ORDS HTTP 응답 없음"
fi

log "2/2 SQL smoke test"
"$SQLCL" -S /nolog <<EOF
connect $ADMIN_USER/"$ADMIN_PASSWORD"@$ADB_TNS
@$REPO_ROOT/sql/smoke_test.sql
exit
EOF

ok "smoke 완료"
