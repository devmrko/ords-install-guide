# ============================================================
# scripts/lib/common.sh
# 모든 스텝 스크립트가 source 합니다.
# ============================================================

# 색
_R='\033[0;31m'; _G='\033[0;32m'; _Y='\033[0;33m'; _B='\033[0;34m'; _N='\033[0m'

log()  { printf "${_B}[%(%H:%M:%S)T]${_N} %s\n" -1 "$*"; }
ok()   { printf "${_G}[OK]${_N} %s\n" "$*"; }
warn() { printf "${_Y}[WARN]${_N} %s\n" "$*" >&2; }
err()  { printf "${_R}[ERR]${_N} %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

# sudo 필요 명령 래퍼 (이미 root면 그냥 실행)
as_root() {
  if [[ $EUID -eq 0 ]]; then "$@"; else sudo "$@"; fi
}

# .env 로드 + 필수 변수 검증
require_env() {
  local missing=()
  for v in "$@"; do
    [[ -z "${!v:-}" ]] && missing+=("$v")
  done
  if (( ${#missing[@]} > 0 )); then
    die ".env 누락 변수: ${missing[*]}"
  fi
}

# 명령 존재 확인
need_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "필요 명령 없음: $c (먼저 설치: yum install -y $c / apt install -y $c)"
  done
}

# wget 공통 옵션
WGET_OPTS="-nv --tries=3 --timeout=30 --retry-connrefused"
fetch() {
  local url="$1" dest="$2"
  log "fetch $url"
  as_root wget $WGET_OPTS -O "$dest" "$url"
}

# 로그 디렉토리 + tee
init_logging() {
  local logdir="$REPO_ROOT/logs"
  mkdir -p "$logdir"
  LOG_FILE="$logdir/run-$(date +%Y%m%d-%H%M%S).log"
  exec > >(tee -a "$LOG_FILE") 2>&1
  log "log file: $LOG_FILE"
}
