# shellcheck shell=bash

settings_eligible() {
    local status
    enabled "$1" || return 1
    status=$(state "$1")
    case "$status" in 완료|유지) return 0;; esac
    [ "$MODE" = dry-run ] && [ "$status" = 예정 ]
}
shell_block() {
    printf '# >>> dev-environment-setup >>>\n'
    shell_section homebrew homebrew
    shell_section oh-my-zsh oh_my_zsh
    shell_section nvm nvm
    shell_section mamba mamba
    shell_section krew krew cnpg
    shell_section local-bin ncp_iam_authenticator terraform
    printf '# <<< dev-environment-setup <<<\n'
}
shell_section() {
    local template=$1 on=false id target="${ZDOTDIR:-$HOME}/.zshrc"
    shift
    for id in "$@"; do if settings_eligible "$id"; then on=true; fi; done
    if [ "$on" = true ]; then
        printf '# dev-environment-setup tool: %s\n' "$template"
        cat "$ROOT/templates/$template.zsh"
        printf '# dev-environment-setup end: %s\n' "$template"
    elif [ -f "$target" ]; then
        # Disabling/failing a tool does not remove its previously installed initialization.
        awk -v name="$template" '
          $0=="# >>> dev-environment-setup >>>" {managed=1;next}
          $0=="# <<< dev-environment-setup <<<" {managed=0;next}
          managed && $0=="# dev-environment-setup tool: " name {copy=1}
          managed && copy {print}
          $0=="# dev-environment-setup end: " name {copy=0}
        ' "$target"
    fi
}
configure_shell() {
    local block="$SESSION/shell-block" candidate="$SESSION/zshrc" target="${ZDOTDIR:-$HOME}/.zshrc" managed=false
    shell_block > "$block"
    # Do not remove a previous block just because all its tools are disabled.
    [ "$(wc -l < "$block")" -gt 2 ] || return 0
    if [ "$(awk -F '|' '$1=="shell"{print $2}' "$SESSION/config")" != true ]; then
        printf '\n셸 초기화 비활성화. 필요한 범용 초기화 코드:\n'; cat "$block"; return 0
    fi
    if [ -L "$target" ]; then printf '\n셸 설정: 심볼릭 링크를 보존합니다. 초기화 코드를 수동 적용하세요.\n'; RUN_FAILED=1; return; fi
    if [ -f "$target" ]; then
        # Reject malformed/duplicate managed blocks rather than deleting unrelated text.
        if ! awk '
          /^# >>> dev-environment-setup >>>$/ {if(open || seen++) exit 1; open=1; next}
          /^# <<< dev-environment-setup <<<$/ {if(!open) exit 1; open=0; next}
          END {if(open) exit 1}
        ' "$target"; then printf '\n셸 관리 구역 형식 오류: 수동 확인 필요\n'; RUN_FAILED=1; return; fi
        awk '
          /^# >>> dev-environment-setup >>>$/ {skip=1;next}
          /^# <<< dev-environment-setup <<<$/ {skip=0;next}
          !skip {print}
        ' "$target" > "$candidate"
    else : > "$candidate"; fi
    cat "$block" >> "$candidate"
    if [ -f "$target" ] && cmp -s "$candidate" "$target"; then printf '\n셸 설정: 유지\n'; return; fi
    case "$MODE" in
        check) printf '\n셸 설정: 초기화 적용 필요\n'; RUN_FAILED=1;;
        dry-run) printf '\n셸 설정: 백업 후 범용 초기화 구역 적용 예정\n';;
        apply)
            if [ -f "$target" ]; then cp -p "$target" "$RUN_DIR/zshrc.backup" || { RUN_FAILED=1; return; }; fi
            mkdir -p "$(dirname "$target")" || { RUN_FAILED=1; return; }
            cp "$candidate" "$target.dev-setup-new" && mv "$target.dev-setup-new" "$target" || { RUN_FAILED=1; return; }
            printf '\n셸 설정: 범용 초기화 적용 완료\n';;
    esac
}
configure_extensions() {
    local type ide ext cli installed extensions_dir
    if grep -q '^extension|' "$SESSION/config"; then printf '\n[IDE 확장]\n'; fi
    while IFS='|' read -r type ide ext; do
        [ "$type" = extension ] || continue
        if ! settings_eligible "$ide"; then printf 'IDE 확장 %s: tools.%s.enabled 및 IDE 설치 상태를 확인하세요.\n' "$ext" "$ide"; RUN_FAILED=1; continue; fi
        tool "$ide"
        cli=$(find_command "$COMMAND") || cli=
        if [ -z "$cli" ]; then
            for cli in "/Applications/$APP/Contents/Resources/app/bin/code" "$HOME/Applications/$APP/Contents/Resources/app/bin/code"; do [ ! -x "$cli" ] || break; done
        fi
        if [ ! -x "$cli" ]; then
            if [ "$MODE" = dry-run ]; then printf 'IDE 확장 %s: IDE 설치 후 추가 예정\n' "$ext";
            else printf 'IDE 확장 %s: IDE CLI 설치 필요\n' "$ext"; RUN_FAILED=1; fi
            continue
        fi
        case "$ide" in vscode) extensions_dir="$HOME/.vscode/extensions";; cursor) extensions_dir="$HOME/.cursor/extensions";; kiro) extensions_dir="$HOME/.kiro/extensions";; esac
        if [ -d "$extensions_dir" ]; then
            installed=$("$cli" --user-data-dir "$SESSION/$ide-user-data" --extensions-dir "$extensions_dir" --list-extensions 2>>"$ERROR_LOG") || { printf 'IDE 확장 조회 실패\n'; RUN_FAILED=1; continue; }
        else installed=; fi
        if printf '%s\n' "$installed" | grep -Fxiq "$ext"; then printf 'IDE 확장 %s: 기존 설치 유지\n' "$ext"; continue; fi
        case "$MODE" in
            apply) if private_run "$cli" --user-data-dir "$SESSION/$ide-user-data" --extensions-dir "$extensions_dir" --install-extension "$ext"; then printf 'IDE 확장 %s: 설치 완료\n' "$ext"; else printf 'IDE 확장 %s: 설치 실패\n' "$ext"; RUN_FAILED=1; fi;;
            dry-run) printf 'IDE 확장 %s: 최신 안정 버전 설치 예정\n' "$ext";;
            check) printf 'IDE 확장 %s: 미설치\n' "$ext"; RUN_FAILED=1;;
        esac
    done < "$SESSION/config"
}
