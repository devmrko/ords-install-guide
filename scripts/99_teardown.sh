#!/usr/bin/env bash
# ============================================================
# 99_teardown.sh
# - systemd 중지/제거
# - ORDS_CONFIG 비우기 (옵션)
# - LB 는 terraform destroy 로 별도
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ORDS_CONFIG

read -rp "정말 teardown? (y/N) " ans
[[ "$ans" =~ ^[yY]$ ]] || { log "취소"; exit 0; }

if as_root systemctl list-unit-files | grep -q '^ords.service'; then
  as_root systemctl stop ords || true
  as_root systemctl disable ords || true
  as_root rm -f /etc/systemd/system/ords.service
  as_root systemctl daemon-reload
  ok "systemd ords 제거"
fi

read -rp "ORDS_CONFIG ($ORDS_CONFIG) 도 삭제? (y/N) " ans
if [[ "$ans" =~ ^[yY]$ ]]; then
  as_root rm -rf "$ORDS_CONFIG"
  ok "config 삭제"
fi

warn "ORDS_HOME / JAVA_HOME / wallet 은 보존 (수동 삭제)"
warn "LB 는 ./run.sh ha-tf destroy 로 별도 정리"
