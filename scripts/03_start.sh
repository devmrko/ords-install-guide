#!/usr/bin/env bash
# ============================================================
# 03_start.sh
# - systemd unit 템플릿을 envsubst 로 치환 → /etc/systemd/system/ords.service
# - enable + start
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ORDS_HOME ORDS_CONFIG JAVA_HOME ORDS_USER ORDS_PORT

UNIT_TMPL="$REPO_ROOT/config/ords.service.tmpl"
UNIT_DST=/etc/systemd/system/ords.service
[[ -f "$UNIT_TMPL" ]] || die "템플릿 없음: $UNIT_TMPL"

log "systemd unit 렌더링"
export ORDS_HOME ORDS_CONFIG JAVA_HOME ORDS_USER ORDS_PORT
envsubst < "$UNIT_TMPL" | as_root tee "$UNIT_DST" >/dev/null

as_root systemctl daemon-reload
as_root systemctl enable ords
as_root systemctl restart ords

sleep 2
if as_root systemctl is-active ords >/dev/null; then
  ok "ords 기동됨 (port $ORDS_PORT)"
else
  err "ords 기동 실패 — journalctl -u ords -n 50 확인"
  as_root journalctl -u ords -n 30 --no-pager
  exit 1
fi
