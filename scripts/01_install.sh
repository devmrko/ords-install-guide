#!/usr/bin/env bash
# ============================================================
# 01_install.sh
# - ORDS zip 다운로드 → /opt/oracle/ords/ords-X.Y.Z → /opt/oracle/ords/current symlink
# - sqlcl 도 같은 방식으로 (smoke test 용)
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ORDS_HOME ORDS_URL SQLCL_URL DOWNLOAD_DIR ORDS_USER ORDS_GROUP

ORDS_BASE=/opt/oracle/ords      # versioned 디렉토리들이 들어가는 부모
SQLCL_BASE=/opt/oracle          # sqlcl 도 같이

if [[ -L "$ORDS_HOME" && -x "$ORDS_HOME/bin/ords" ]]; then
  ok "ORDS 이미 설치됨: $($ORDS_HOME/bin/ords --version 2>/dev/null || echo unknown)"
else
  log "1/3 ORDS 다운로드"
  fetch "$ORDS_URL" "$DOWNLOAD_DIR/ords.zip"

  # zip 안 최상위 디렉토리 이름이 보통 'ords-X.Y.Z'
  TMP=$(mktemp -d)
  as_root unzip -q "$DOWNLOAD_DIR/ords.zip" -d "$TMP"
  TOP=$(ls -1 "$TMP" | head -1)
  VERSIONED="$ORDS_BASE/$TOP"

  log "2/3 배치: $VERSIONED"
  as_root mv "$TMP/$TOP" "$VERSIONED"
  rm -rf "$TMP"

  log "3/3 alias symlink: $ORDS_HOME -> $VERSIONED"
  as_root ln -sfn "$VERSIONED" "$ORDS_HOME"
  as_root chown -R "$ORDS_USER:$ORDS_GROUP" "$VERSIONED" "$ORDS_HOME"
  ok "ORDS 설치 완료"
fi

# sqlcl
SQLCL_LINK="$SQLCL_BASE/sqlcl"
if [[ -x "$SQLCL_LINK/bin/sql" ]]; then
  ok "sqlcl 이미 있음"
else
  log "sqlcl 다운로드"
  fetch "$SQLCL_URL" "$DOWNLOAD_DIR/sqlcl.zip"
  as_root unzip -q -o "$DOWNLOAD_DIR/sqlcl.zip" -d "$SQLCL_BASE"
  as_root chown -R "$ORDS_USER:$ORDS_GROUP" "$SQLCL_LINK"
  ok "sqlcl 설치 완료"
fi
