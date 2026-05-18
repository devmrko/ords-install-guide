#!/usr/bin/env bash
# ============================================================
# 00_prereq.sh
# - 필수 명령 확인 (wget, unzip, tar)
# - oracle 유저/그룹 생성
# - 디렉토리 생성
# - JDK 다운로드 → /opt/java/jdk-X.Y.Z → /opt/java/current symlink
# ============================================================
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$REPO_ROOT/.env"
source "$REPO_ROOT/scripts/lib/common.sh"

require_env ORDS_USER ORDS_GROUP JAVA_HOME JDK_URL DOWNLOAD_DIR

log "0/4 명령 확인"
need_cmd wget unzip tar curl

log "1/4 oracle 유저/그룹"
getent group  "$ORDS_GROUP" >/dev/null || as_root groupadd "$ORDS_GROUP"
getent passwd "$ORDS_USER"  >/dev/null || as_root useradd -m -g "$ORDS_GROUP" "$ORDS_USER"

log "2/4 디렉토리"
as_root mkdir -p "$DOWNLOAD_DIR" /opt/java /opt/oracle/ords /etc/ords
as_root chown -R "$ORDS_USER:$ORDS_GROUP" /opt/oracle/ords /etc/ords

log "3/4 JDK 다운로드"
JDK_DIR=/opt/java
if [[ -L "$JAVA_HOME" && -x "$JAVA_HOME/bin/java" ]]; then
  ok "JDK 이미 설치됨: $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
else
  fetch "$JDK_URL" "$DOWNLOAD_DIR/jdk.tar.gz"
  as_root tar -xzf "$DOWNLOAD_DIR/jdk.tar.gz" -C "$JDK_DIR"
  NEW_JDK=$(ls -1dt $JDK_DIR/jdk-* 2>/dev/null | head -1)
  [[ -z "$NEW_JDK" ]] && die "tar 풀린 jdk-* 디렉토리 못 찾음"
  log "4/4 alias symlink: $JAVA_HOME -> $NEW_JDK"
  as_root ln -sfn "$NEW_JDK" "$JAVA_HOME"
  ok "JDK: $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
fi

# 시스템 PATH (다음 셸 세션부터 적용)
PROFILE=/etc/profile.d/ords-java.sh
if [[ ! -f "$PROFILE" ]] || ! grep -q "$JAVA_HOME" "$PROFILE" 2>/dev/null; then
  as_root tee "$PROFILE" >/dev/null <<EOF
export JAVA_HOME=$JAVA_HOME
export PATH=\$JAVA_HOME/bin:\$PATH
EOF
  ok "PATH 등록: $PROFILE (재로그인 후 적용)"
fi

ok "prereq 완료"
