# shellcheck shell=bash

json() { /usr/bin/osascript -l JavaScript "$ROOT/lib/json.js" "$@" 2>>"${ERROR_LOG:-/dev/null}"; }
tool() {
    local row
    row=$(awk -F '|' -v key="$1" '$1 == key { print; exit }' "$ROOT/lib/catalog.tsv")
    [ -n "$row" ] || return 1
    IFS='|' read -r ID GROUP LABEL ROLE ADAPTER PACKAGE COMMAND APP BUNDLE UPSTREAM DEPS URL <<< "$row"
}
config_value() { awk -F '|' -v id="$1" -v n="$2" '$1=="tool" && $2==id {print $n}' "$SESSION/config"; }
enabled() { [ "$(config_value "$1" 3)" = true ]; }
replace_allowed() { [ "$(config_value "$1" 4)" = true ]; }
state() { [ ! -f "$SESSION/$1.status" ] || cat "$SESSION/$1.status"; }
normal_version() {
    local v=${1#v}
    case "${ADAPTER:-}" in cask|dmg_app) v=${v%%,*};; esac
    printf '%s' "${v%%+*}"
}
extract_version() { sed -nE 's/^[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?([._+-][0-9A-Za-z.-]+)?).*$/\1/p' | head -n 1; }
version_ge() {
    awk -v a="$1" -v b="$2" 'BEGIN {split(a,x,".");split(b,y,".");for(i=1;i<=4;i++){if(x[i]+0>y[i]+0)exit 0;if(x[i]+0<y[i]+0)exit 1}exit 0}'
}
safe_path() {
    case "$1" in "$HOME"/*) printf '$HOME/%s' "${1#"$HOME"/}";; /Users/*|/home/*) printf '<사용자 경로>';; *) printf '%s' "$1";; esac
}
result() {
    local outcome=$1 message=$2
    printf '%s\n' "$outcome" > "$SESSION/$ID.status"
    printf '%s\n' "$message" > "$SESSION/$ID.reason"
    case "$outcome" in 실패|차단|수동작업|확인필요|미설치) RUN_FAILED=1;; esac
}
http() {
    case "$1" in https://*) ;; *) return 1;; esac
    /usr/bin/curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
        --connect-timeout 10 --max-time 90 --retry 2 -o "$2" "$1" 2>>"$ERROR_LOG"
}
private_run() { "$@" >>"$ERROR_LOG" 2>&1; }
brew_cmd() {
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
    HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1 HOMEBREW_NO_ANALYTICS=1 HOMEBREW_NO_ENV_HINTS=1 \
    "$BREW" "$@"
}
find_command() {
    local name=$1 p
    [ "$name" != - ] || return 1
    # Respect an existing PATH entry; fallback paths do not change the user's PATH.
    p=$(type -P "$name" 2>/dev/null) && { printf '%s' "$p"; return; }
    for p in "/opt/homebrew/bin/$name" "$HOME/.local/bin/$name" "$HOME/bin/$name" "${KREW_ROOT:-$HOME/.krew}/bin/$name"; do
        if [ -x "$p" ]; then printf '%s' "$p"; return; fi
    done
    return 1
}
plist() { /usr/libexec/PlistBuddy -c "Print :$2" "$1/Contents/Info.plist" 2>/dev/null; }
bundle_matches() { case ",$BUNDLE," in *",$1,"*) return 0;; *) return 1;; esac; }
locate_app() {
    local p
    # Prefer the expected name, then recognize renamed apps by their bundle ID.
    for p in "/Applications/$APP" "$HOME/Applications/$APP"; do
        if [ -d "$p" ]; then printf '%s' "$p"; return; fi
    done
    for p in /Applications/*.app "$HOME"/Applications/*.app; do
        [ -d "$p" ] || continue
        if bundle_matches "$(plist "$p" CFBundleIdentifier)"; then printf '%s' "$p"; return; fi
    done
    return 1
}
detect() {
    PRESENT=false CURRENT=- ORIGIN=unknown BIN=- FOUND_APP=-
    local p v record
    case "$ADAPTER" in
        clt)
            if /usr/bin/xcode-select -p >/dev/null 2>&1; then
                PRESENT=true; ORIGIN=apple; CURRENT=$(/usr/sbin/pkgutil --pkg-info com.apple.pkg.CLTools_Executables 2>/dev/null | awk '/^version:/{print $2}')
                [ -n "$CURRENT" ] || CURRENT=unknown
            fi
            return;;
        omz)
            p=${ZSH:-$HOME/.oh-my-zsh}
            if [ -d "$p" ]; then
                PRESENT=true; BIN=$p; ORIGIN=external; CURRENT=unknown
                if [ -d "$p/.git" ]; then CURRENT=$(git -C "$p" rev-parse HEAD 2>/dev/null) || CURRENT=unknown; fi
                [ ! -f "$p/.dev-setup-version" ] || { CURRENT=$(cat "$p/.dev-setup-version"); ORIGIN=managed; }
            fi
            return;;
        nvm)
            p=${NVM_DIR:-$HOME/.nvm}
            if [ -d "$p" ]; then
                PRESENT=true; BIN=$p; CURRENT=unknown; ORIGIN=external
                [ ! -f "$p/nvm.sh" ] || CURRENT=$(/bin/bash -c '. "$1" --no-use >/dev/null 2>&1; nvm --version' bash "$p/nvm.sh" 2>/dev/null)
                [ ! -f "$p/.dev-setup-version" ] || ORIGIN=managed
                [ -n "$CURRENT" ] || CURRENT=unknown
            fi
            return;;
        mamba)
            for p in "${MAMBA_ROOT_PREFIX:-$HOME/miniforge3}" "$HOME/mambaforge" /opt/homebrew/Caskroom/miniforge/base; do
                if [ -x "$p/bin/mamba" ]; then BIN=$p/bin/mamba; break; fi
            done;;
    esac
    if [ "$APP" != - ]; then
        if p=$(locate_app); then
                PRESENT=true; FOUND_APP=$p; BIN=$p; ORIGIN=external
                CURRENT=$(plist "$p" CFBundleShortVersionString) || CURRENT=unknown
                # A name collision is never permission to replace an unrelated app.
                if ! bundle_matches "$(plist "$p" CFBundleIdentifier)"; then CURRENT=unknown; return; fi
        fi
    fi
    if [ "$BIN" = - ]; then BIN=$(find_command "$COMMAND") || BIN=-; fi
    if [ "$BIN" != - ] && [ "$FOUND_APP" = - ]; then
        if [ "$BIN" = /usr/bin/git ] && ! /usr/bin/xcode-select -p >/dev/null 2>&1; then BIN=-; return; fi
        PRESENT=true
        case "$ID" in
            kubectl) if v=$(KUBECONFIG=/dev/null "$BIN" version --client --output=json 2>>"$ERROR_LOG"); then
                    CURRENT=$(printf '%s' "$v" | sed -nE 's/.*"gitVersion": *"v?([^"]+)".*/\1/p' | head -1)
                else CURRENT=unknown; fi;;
            helm) CURRENT=$(KUBECONFIG=/dev/null "$BIN" version --short 2>>"$ERROR_LOG" | extract_version) || CURRENT=unknown;;
            k9s) CURRENT=$(KUBECONFIG=/dev/null "$BIN" version --short 2>>"$ERROR_LOG" | extract_version) || CURRENT=unknown;;
            krew) CURRENT=$(KUBECONFIG=/dev/null "$BIN" version 2>>"$ERROR_LOG" | awk '/GitTag/{print $2}' | sed 's/^v//') || CURRENT=unknown;;
            cnpg) CURRENT=$(KUBECONFIG=/dev/null "$BIN" version 2>>"$ERROR_LOG" | extract_version) || CURRENT=unknown;;
            ncp_iam_authenticator) CURRENT=$(KUBECONFIG=/dev/null "$BIN" version 2>>"$ERROR_LOG" | extract_version) || CURRENT=unknown;;
            *) CURRENT=$("$BIN" --version 2>>"$ERROR_LOG" | extract_version) || CURRENT=unknown;;
        esac
    fi
    if [ "$PACKAGE" != - ] && [ -n "$BREW" ] && { [ "$ADAPTER" = formula ] || [ "$ADAPTER" = cask ]; }; then
        record=$(brew_cmd list --versions "--$ADAPTER" "$PACKAGE" 2>/dev/null) || record=
        if [ -n "$record" ]; then
            if [ "$PRESENT" != true ]; then PRESENT=true; CURRENT=unknown; fi
            case "$BIN" in /opt/homebrew/*|/Applications/*)
                ORIGIN=homebrew
                # Casks use application version; formula records retain revisions.
                if [ -n "$CURRENT" ] && [ "$CURRENT" != unknown ] && { [ "$ADAPTER" = formula ] || [ "$FOUND_APP" = - ]; }; then CURRENT=$(printf '%s\n' "$record" | awk '{print $NF}'); fi;;
            esac
        fi
    fi
    case "$ADAPTER" in
        brew_bootstrap) [ "$PRESENT" != true ] || ORIGIN=homebrew;;
        krew|cnpg) case "$BIN" in "${KREW_ROOT:-$HOME/.krew}"/*) ORIGIN=krew;; esac;;
        ncp|terraform) if [ "$BIN" = "$HOME/.local/bin/$COMMAND" ] && [ -f "$STATE_ROOT/receipts/$ID" ]; then ORIGIN=managed; fi;;
        orca|cua_app|dmg_app) if [ "$FOUND_APP" = "$HOME/Applications/$APP" ] && [ -f "$STATE_ROOT/receipts/$ID" ]; then ORIGIN=managed; fi;;
    esac
    [ -n "$CURRENT" ] || CURRENT=unknown
}
save_detection() { printf '%s|%s|%s|%s\n' "$PRESENT" "$CURRENT" "$ORIGIN" "$BIN" > "$SESSION/$ID.detect"; }
dependency_ready() (
    local dep=$1 status
    tool "$dep" || exit 1
    detect
    if [ "$PRESENT" = true ]; then [ "${CURRENT:-unknown}" != unknown ]; exit $?; fi
    status=$(state "$dep")
    [ "$MODE" != check ] && [ "$status" = 예정 ] && [ "$MODE" = dry-run ]
)
dependencies_ok() {
    local dep
    [ "$DEPS" != - ] || return 0
    for dep in ${DEPS//,/ }; do
        if ! dependency_ready "$dep"; then
            REASON="선행 도구 $dep 필요: tools.$dep.enabled 설정 및 해당 도구의 결과를 확인하세요."
            return 1
        fi
    done
}
decide() {
    ACTION=keep REASON=
    if [ "$PRESENT" = true ] && [ "$CURRENT" = unknown ]; then ACTION=manual; REASON='기존 버전 또는 설치 출처 확인 필요'; return; fi
    if [ "$(normal_version "$CURRENT")" = "$(normal_version "$TARGET")" ] && [ "$PRESENT" = true ]; then return; fi
    if [ "$PRESENT" = true ] && ! replace_allowed "$ID"; then REASON='기존 버전 유지 (재설치 비허용)'; return; fi
    if [ "$PRESENT" = true ]; then
        ACTION=replace
        case "$ORIGIN:$ADAPTER" in
            homebrew:formula|homebrew:cask|homebrew:brew_bootstrap|managed:ncp|managed:terraform|managed:orca|managed:cua_app|managed:dmg_app|krew:cnpg|krew:krew) ;;
            *) ACTION=manual; REASON='기존 설치와 사용자 데이터 보존을 위해 수동 교체 필요';;
        esac
    else ACTION=install; fi
}
process_tool() {
    tool "$1" || return 1
    TARGET=-
    if ! enabled "$ID"; then result 비활성화 'config에서 선택하지 않음'; return; fi
    detect; save_detection
    if [ "$ADAPTER" = manual ]; then
        result 수동작업 "공식 설치 안내: $URL (개인 설정 가져오기 및 부가 설치는 선택하지 마세요.)"; return
    fi
    if [ "$ADAPTER" = clt ]; then
        if [ "$PRESENT" = true ]; then result 유지 'Apple 관리 도구; 최신 여부는 시스템 소프트웨어 업데이트에서 확인';
        else
            if [ "$MODE" = apply ]; then private_run /usr/bin/xcode-select --install || :; fi
            result 수동작업 'xcode-select --install로 설치를 완료한 뒤 재실행하세요.'
        fi
        return
    fi
    if ! resolve_target; then result 확인필요 "최신 안정 버전 조회 실패; 설치·교체하지 않음. $URL"; return; fi
    printf '%s\n' "$TARGET" > "$SESSION/$ID.target"
    decide
    case "$ACTION" in
        keep) result 유지 "${REASON:-목표 버전 일치}"; return;;
        manual) result 수동작업 "$REASON; $URL"; return;;
    esac
    if ! dependencies_ok; then result 차단 "$REASON"; return; fi
    if ! preflight_adapter; then result 차단 "$REASON; $URL"; return; fi
    if [ "$MODE" = check ]; then result 미설치 '설치 또는 허용된 버전 교체 필요'; return; fi
    if [ "$MODE" = dry-run ]; then result 예정 "$ACTION; ${DETAIL:-선택한 도구만 처리}"; return; fi
    printf '진행: %s — %s\n' "$LABEL" "$ACTION"
    if ! install_adapter; then result 실패 "설치·교체 실패; 같은 config로 재시도하거나 $URL 확인"; return; fi
    detect; save_detection
    if [ "$PRESENT" != true ] || [ "$CURRENT" = unknown ]; then result 실패 '설치 후 로컬 실행 파일·버전 확인 실패'; return; fi
    if [ "$(normal_version "$CURRENT")" != "$(normal_version "$TARGET")" ]; then result 실패 '설치 후 목표 버전과 불일치'; return; fi
    result 완료 '로컬 실행 파일·버전 확인 완료'
}
report() {
    local id group last_group= outcome reason current target path
    printf '\n실행 결과 (%s)\n' "$MODE"
    while IFS='|' read -r id group _; do
        case "$id" in ''|'#'*) continue;; esac
        if [ "$group" != "$last_group" ]; then printf '\n[%s]\n' "$group"; last_group=$group; fi
        tool "$id"
        outcome=$(state "$id"); reason=$(cat "$SESSION/$id.reason" 2>/dev/null)
        current=-; target=-; path=-
        if [ -f "$SESSION/$id.detect" ]; then IFS='|' read -r _ current _ path < "$SESSION/$id.detect"; fi
        [ ! -f "$SESSION/$id.target" ] || target=$(cat "$SESSION/$id.target")
        printf '%s (%s): %s | 현재 %s → 목표 %s | %s\n' "$LABEL" "$ROLE" "$outcome" "$current" "$target" "$reason"
        if [ "$MODE" = check ] && [ "$path" != - ]; then printf '  실행 경로: %s\n' "$(safe_path "$path")"; fi
    done < "$ROOT/lib/catalog.tsv"
    [ ! -f "$SESSION/settings-report" ] || cat "$SESSION/settings-report"
}
usage() {
    cat <<'EOF'
사용: bash setup.sh [--config FILE] [--dry-run | --check]
  기본 실행     선택 도구 설치, 허용된 버전 교체, 범용 설정 적용
  --dry-run     변경 없이 예정 작업과 차단 사유 확인
  --check       변경 없이 로컬 설치·버전·설정 확인
  --help        도움말
종료 코드: 0 완료/정책에 따른 유지, 1 미완료, 2 설정·환경 오류
EOF
}
cleanup() {
    if [ -n "${MOUNTED_VOLUME:-}" ]; then
        /usr/bin/hdiutil detach "$MOUNTED_VOLUME" >/dev/null 2>&1 || { printf '임시 디스크 이미지를 해제하지 못했습니다. 디스크 유틸리티에서 확인하세요.\n' >&2; return; }
    fi
    [ -z "${SESSION:-}" ] || /bin/rm -rf "$SESSION"
}
main() {
    MODE=apply RUN_FAILED=0 BREW= SESSION= MOUNTED_VOLUME=
    STATE_ROOT="$HOME/Library/Application Support/dev-environment-setup"
    local config="$ROOT/config.local.json" explicit=false id
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --help|-h) usage; return 0;;
            --config) [ "$#" -ge 2 ] || { usage; return 2; }; config=$2; explicit=true; shift;;
            --dry-run|--check) [ "$MODE" = apply ] || { usage; return 2; }; MODE=${1#--};;
            *) usage; return 2;;
        esac
        shift
    done
    if [ "$explicit" = false ] && [ ! -f "$config" ]; then config="$ROOT/config.example.json"; fi
    [ -f "$config" ] || { printf 'config 파일을 찾을 수 없습니다.\n' >&2; return 2; }
    [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] || { printf 'Apple Silicon macOS에서 실행하세요. Rosetta 셸은 지원하지 않습니다.\n' >&2; return 2; }
    [ "$(id -u)" != 0 ] || { printf 'sudo로 전체 스크립트를 실행하지 마세요.\n' >&2; return 2; }
    SESSION=$(mktemp -d "${TMPDIR:-/tmp}/dev-environment-setup.XXXXXXXX") || return 2
    ERROR_LOG="$SESSION/diagnostics.log"
    trap cleanup EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    if ! json config "$config" "$ROOT/lib/catalog.tsv" > "$SESSION/config"; then
        printf 'config 검증 실패: 키·자료형·schema_version·확장 ID를 확인하세요.\n' >&2; return 2
    fi
    MACOS_VERSION=$(/usr/bin/sw_vers -productVersion)
    case "${MACOS_VERSION%%.*}" in
        11) OS_TAG=arm64_big_sur;; 12) OS_TAG=arm64_monterey;; 13) OS_TAG=arm64_ventura;;
        14) OS_TAG=arm64_sonoma;; 15) OS_TAG=arm64_sequoia;; 26) OS_TAG=arm64_tahoe;; 27) OS_TAG=arm64_golden_gate;; *) OS_TAG=unsupported;;
    esac
    BREW=$(find_command brew) || BREW=
    if [ "$MODE" = apply ]; then
        RUN_DIR="$STATE_ROOT/runs/$(date -u +%Y%m%dT%H%M%SZ)-$$"
        mkdir -p "$RUN_DIR" "$STATE_ROOT/receipts" || return 2
        ERROR_LOG="$RUN_DIR/diagnostics.log"
        : > "$ERROR_LOG"
    fi
    printf '개인 설정을 가져오지 않습니다. 클러스터 접속 없이 로컬 도구만 검사합니다.\n'
    while IFS='|' read -r id _; do
        case "$id" in ''|'#'*) continue;; esac
        process_tool "$id"
        [ "$id" != homebrew ] || { BREW=$(find_command brew) || BREW=; }
    done < "$ROOT/lib/catalog.tsv"
    configure_shell > "$SESSION/settings-report"
    configure_extensions >> "$SESSION/settings-report"
    report
    if [ "$MODE" = apply ]; then report > "$RUN_DIR/report.txt"; printf '\n로그·백업: $HOME/Library/Application Support/dev-environment-setup/runs/\n'; fi
    return "$RUN_FAILED"
}
