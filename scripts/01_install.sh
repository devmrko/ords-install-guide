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

if [[ -L "$ORDS_HOME" && -x "$ORDS_HOME/bin/ords" && -f "$ORDS_HOME/ords.war" ]]; then
  ok "ORDS 이미 설치됨: $($ORDS_HOME/bin/ords --version 2>/dev/null || echo unknown)"
else
  log "1/3 ORDS 다운로드"
  fetch "$ORDS_URL" "$DOWNLOAD_DIR/ords.zip"

  # ORDS zip layout 두 가지:
  #   (a) 단일 top-level 디렉토리 (ords-X.Y.Z/...) — 그걸 그대로 mv
  #   (b) flat (LICENSE.txt, ords.war, bin/, lib/, ... 가 zip 루트에 깔림) — 24.x/26.x
  # 우선 zip 의 top-level 엔트리들을 파싱해서 분기.
  mapfile -t TOPS < <(unzip -Z1 "$DOWNLOAD_DIR/ords.zip" | awk -F/ 'NF{print $1}' | sort -u)

  if [[ ${#TOPS[@]} -eq 1 && "${TOPS[0]}" =~ ^ords- ]]; then
    # (a) 단일 top dir — 그 이름이 곧 버전 디렉토리
    TOP="${TOPS[0]}"
    VERSIONED="$ORDS_BASE/$TOP"
    if [[ -d "$VERSIONED" && -f "$VERSIONED/ords.war" ]]; then
      log "2/3 동일 버전 디렉토리 이미 존재 — 재배치 skip: $VERSIONED"
    else
      TMP=$(mktemp -d); trap 'as_root rm -rf "$TMP"' EXIT INT TERM
      as_root unzip -q "$DOWNLOAD_DIR/ords.zip" -d "$TMP"
      log "2/3 배치: $VERSIONED"
      as_root rm -rf "$VERSIONED"
      as_root mv "$TMP/$TOP" "$VERSIONED"
    fi
  else
    # (b) flat — 버전을 zip 안에서 추출해서 versioned dir 생성
    #     ords-plugin-* jar 이름에서 X.Y.Z 추출 (ex: ords-plugin-apt-26.1.1.132.1130.jar)
    VER=$(unzip -Z1 "$DOWNLOAD_DIR/ords.zip" \
            | grep -m1 -oE 'ords-plugin-[a-z]+-[0-9]+\.[0-9]+\.[0-9]+' \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    [[ -z "$VER" ]] && VER=$(date +%Y%m%d-%H%M%S)
    VERSIONED="$ORDS_BASE/ords-$VER"
    if [[ -d "$VERSIONED" && -f "$VERSIONED/ords.war" ]]; then
      log "2/3 동일 버전 디렉토리 이미 존재 — 재배치 skip: $VERSIONED"
    else
      log "2/3 배치 (flat zip → $VERSIONED)"
      as_root rm -rf "$VERSIONED"
      as_root mkdir -p "$VERSIONED"
      as_root unzip -q -o "$DOWNLOAD_DIR/ords.zip" -d "$VERSIONED"
    fi
  fi

  log "3/3 alias symlink: $ORDS_HOME -> $VERSIONED"
  as_root ln -sfn "$VERSIONED" "$ORDS_HOME"
  as_root chown -RH "$ORDS_USER:$ORDS_GROUP" "$VERSIONED" "$ORDS_HOME"
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
