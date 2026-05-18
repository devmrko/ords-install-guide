#!/usr/bin/env bash
# ============================================================
# 05_ha.sh
# - HA 노드 부트스트랩 안내/검증
# - 실제 LB 구성은 06_lb_terraform.sh 또는 docs/04-ha.md §4.4 (웹콘솔)
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env HA_NODE_ROLE HA_NODES ORDS_PORT LB_HEALTHCHECK_PATH

log "HA_NODE_ROLE = $HA_NODE_ROLE"
log "HA_NODES     = $HA_NODES"

case "$HA_NODE_ROLE" in
  primary)
    ok "primary 노드: 정상. 이제 secondary 노드에서도 동일 절차 수행:"
    cat <<EOM

  1) secondary 노드에 이 repo clone
  2) cp .env.example .env  (같은 DB/wallet 정보 사용)
     단, HA_NODE_ROLE=secondary 로 변경
  3) WALLET_PATH 에 ADB wallet 동일하게 배치
  4) ./run.sh all

  → 두 노드 모두 올라오면 ./run.sh ha-tf apply 로 LB 구성
EOM
    ;;
  secondary)
    ok "secondary 노드: 부트스트랩 완료. primary 와 동일하게 응답 확인"
    ;;
  *) die "HA_NODE_ROLE 은 primary|secondary 만 허용";;
esac

# 모든 노드 healthcheck 시도
log "전 노드 healthcheck 매트릭스"
for ip in $HA_NODES; do
  url="http://$ip:$ORDS_PORT$LB_HEALTHCHECK_PATH"
  if curl -fsS --max-time 5 "$url" >/dev/null 2>&1; then
    ok "  $url"
  else
    warn "  $url  (응답 없음)"
  fi
done
