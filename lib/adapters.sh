# shellcheck shell=bash

metadata() {
    local kind=$1 name=$2 file="$SESSION/$1-${2//\//_}.json"
    if [ ! -s "$file" ]; then http "https://formulae.brew.sh/api/$kind/$name.json" "$file" || return 1; fi
    printf '%s' "$file"
}
release_metadata() {
    local repo=$1 file="$SESSION/${1//\//_}-release.json"
    if [ ! -s "$file" ]; then http "https://api.github.com/repos/$repo/releases/latest" "$file" || return 1; fi
    printf '%s' "$file"
}
resolve_target() {
    META= DETAIL=
    case "$ADAPTER" in
        formula|cask)
            META=$(metadata "$ADAPTER" "$PACKAGE") || return 1
            json brew "$META" "$ADAPTER" "$OS_TAG" > "$SESSION/$ID.brew" || return 1
            TARGET=$(awk -F '|' '$1=="version"{print $2}' "$SESSION/$ID.brew");;
        dmg_app)
            META=$(metadata cask "$PACKAGE") || return 1
            json brew "$META" cask "$OS_TAG" > "$SESSION/$ID.brew" || return 1
            TARGET=$(awk -F '|' '$1=="version"{print $2}' "$SESSION/$ID.brew");;
        brew_bootstrap|nvm|krew|ncp|orca)
            META=$(release_metadata "$UPSTREAM") || return 1
            TARGET=$(json release "$META") || return 1;;
        cua_app)
            http "https://api.github.com/repos/$UPSTREAM/releases?per_page=100" "$SESSION/cua-releases.json" || return 1
            META="$SESSION/cua-release.json"
            json cua-release "$SESSION/cua-releases.json" > "$META" || return 1
            TARGET=$(json get "$META" tag_name); TARGET=${TARGET#cua-driver-rs-v};;
        mamba)
            META=$(release_metadata "$UPSTREAM") || return 1
            http 'https://api.anaconda.org/package/conda-forge/mamba' "$SESSION/mamba-package.json" || return 1
            TARGET=$(json get "$SESSION/mamba-package.json" latest_version) || return 1;;
        omz)
            META="$SESSION/omz-commit.json"
            http "https://api.github.com/repos/$UPSTREAM/commits/master" "$META" || return 1
            TARGET=$(json get "$META" sha) || return 1
            [[ "$TARGET" =~ ^[a-f0-9]{40}$ ]] || return 1;;
        cnpg)
            META="$SESSION/cnpg.yaml"
            http 'https://raw.githubusercontent.com/kubernetes-sigs/krew-index/master/plugins/cnpg.yaml' "$META" || return 1
            TARGET=$(awk '/^  version:/{gsub(/["\047]/,"",$2);sub(/^v/,"",$2);print $2}' "$META");;
        terraform)
            META="$SESSION/terraform-release.json"
            http 'https://api.releases.hashicorp.com/v1/releases/terraform/latest' "$META" || return 1
            TARGET=$(json get "$META" version) || return 1;;
        *) return 1;;
    esac
    case "$TARGET" in ''|*nightly*|*alpha*|*beta*|*rc*|*preview*) return 1;; esac
    [[ "$TARGET" =~ ^[0-9a-f][0-9A-Za-z._,+-]*$ ]]
}
brew_dependency_guard() (
    # Recursively inspect runtime dependencies. Never run source builds.
    local name=$1 depth=${2:-0} data lines target installed dep owner
    [ "$depth" -lt 30 ] || exit 1
    [ ! -f "$SESSION/dep-ok-$name" ] || exit 0
    data=$(metadata formula "$name") || exit 1
    lines="$SESSION/dep-$name.tsv"
    json brew "$data" formula "$OS_TAG" > "$lines" || exit 1
    target=$(awk -F '|' '$1=="version"{print $2}' "$lines")
    installed=
    [ -z "$BREW" ] || installed=$(brew_cmd list --versions --formula "$name" 2>/dev/null | awk '{print $NF}')
    if [ -n "$installed" ] && [ "$installed" != "$target" ]; then
        printf '의존 패키지 %s의 기존 버전 변경이 필요합니다.\n' "$name" > "$SESSION/dependency-error"
        exit 1
    fi
    if [ -z "$installed" ]; then
        owner=$(awk -F '|' -v p="$name" '$6==p && $5=="formula" {print $1;exit}' "$ROOT/lib/catalog.tsv")
        if [ -n "$owner" ]; then
            # Dependencies represented in config must have been explicitly enabled.
            enabled "$owner" || { printf '선행 도구 tools.%s.enabled 설정이 필요합니다.\n' "$owner" > "$SESSION/dependency-error"; exit 1; }
        fi
        # Python linking must not change the user's default Python.
        case "$name" in python|python@*|uv|go|openjdk*)
            printf '%s 의존성은 별도 런타임을 직접 설치하므로 수동 처리가 필요합니다.\n' "$name" > "$SESSION/dependency-error"; exit 1;;
        esac
        grep -q '^bottle|true$' "$lines" || exit 1
    fi
    while IFS='|' read -r kind dep; do
        [ "$kind" != dep ] || brew_dependency_guard "$dep" "$((depth + 1))" || exit 1
    done < "$lines"
    : > "$SESSION/dep-ok-$name"
)
preflight_adapter() {
    REASON=
    local kind value bound dep
    case "$ADAPTER" in
        formula|cask|brew_bootstrap)
            if [ -n "$BREW" ] && [ "$(brew_cmd --prefix 2>/dev/null)" != /opt/homebrew ]; then REASON='표준 Apple Silicon Homebrew 경로(/opt/homebrew)가 필요합니다.'; return 1; fi;;
    esac
    case "$ADAPTER" in
        formula|cask)
            grep -q '^bottle|true$' "$SESSION/$ID.brew" || { REASON='현재 macOS용 ARM64 바이너리가 없습니다. 소스 빌드는 수행하지 않습니다.'; return 1; }
            if grep -q '^unsupported|' "$SESSION/$ID.brew"; then REASON='현재 OS 또는 부가 설치 동작을 자동 검증할 수 없습니다. 공식 설치 안내를 이용하세요.'; return 1; fi
            while IFS='|' read -r kind value bound; do
                case "$kind" in
                    macos)
                        case "$value" in
                            '>=' ) version_ge "$MACOS_VERSION" "$bound" || { REASON="macOS $bound 이상 필요"; return 1; };;
                            *) REASON='macOS 버전 제약을 자동 판별할 수 없습니다.'; return 1;;
                        esac;;
                    arch) case "$value" in *arm64*) ;; *) REASON='ARM64 지원을 확인할 수 없습니다.'; return 1;; esac;;
                    dep)
                        if ! brew_dependency_guard "$value"; then
                            REASON=$(cat "$SESSION/dependency-error" 2>/dev/null) || REASON='의존 패키지 ARM64 배포물·버전 확인 실패'
                            return 1
                        fi;;
                esac
            done < "$SESSION/$ID.brew"
            DETAIL="런타임 의존성: $(awk -F '|' '$1=="dep"{printf "%s ",$2}' "$SESSION/$ID.brew")"
            ;;
        mamba)
            [ "$PRESENT" != true ] || { REASON='기존 mamba/base 환경의 자동 교체는 하지 않습니다. 환경을 보존하여 수동 업데이트하세요.'; return 1; }
            [ ! -e "$HOME/miniforge3" ] || { REASON='기존 miniforge3 디렉터리를 보존하기 위해 설치를 중단합니다.'; return 1; };;
        ncp|terraform)
            if [ -e "$HOME/.local/bin/$COMMAND" ] && [ "$ORIGIN" != managed ]; then REASON='설치 위치에 관리되지 않는 파일이 있습니다.'; return 1; fi;;
        nvm) [ ! -e "${NVM_DIR:-$HOME/.nvm}" ] || { REASON='기존 nvm 디렉터리를 보존하여 수동 업데이트하세요.'; return 1; };;
        omz) [ ! -e "${ZSH:-$HOME/.oh-my-zsh}" ] || { REASON='기존 Oh My Zsh 설정을 보존하여 수동 업데이트하세요.'; return 1; };;
        orca|cua_app|dmg_app)
            if [ -e "$HOME/Applications/$APP" ] && [ "$ORIGIN" != managed ]; then REASON='기존 앱을 보존하기 위해 수동 교체가 필요합니다.'; return 1; fi
            if [ "$ADAPTER" = dmg_app ]; then
                if grep -q '^unsupported|macOS/ARM64$' "$SESSION/$ID.brew"; then REASON='현재 macOS/ARM64 배포물을 지원하지 않습니다.'; return 1; fi
                while IFS='|' read -r kind value bound; do
                    [ "$kind" != macos ] || { [ "$value" = '>=' ] && version_ge "$MACOS_VERSION" "$bound"; } || { REASON='앱의 macOS 요구사항을 만족하지 않습니다.'; return 1; }
                done < "$SESSION/$ID.brew"
            fi;;
    esac
    return 0
}
verify_sha() {
    local file=$1 hash=$2 actual
    hash=${hash#sha256:}
    [[ "$hash" =~ ^[a-fA-F0-9]{64}$ ]] || return 1
    actual=$(/usr/bin/shasum -a 256 "$file" | awk '{print $1}') || return 1
    [ "$actual" = "$hash" ]
}
download_asset() {
    local metadata=$1 name=$2 dest=$3 row url digest
    row=$(json asset "$metadata" "$name") || return 1
    IFS='|' read -r url digest <<< "$row"
    http "$url" "$dest" || return 1
    if [ "$digest" != - ]; then verify_sha "$dest" "$digest"; else return 3; fi
}
checksum_from_file() { awk -v f="$2" '{name=$2;sub(/^\*/,"",name);if(name==f) {print $1; exit}}' "$1"; }
asset_with_checksum() {
    local metadata=$1 name=$2 sums=$3 dest=$4 code row url hash
    download_asset "$metadata" "$name" "$dest"; code=$?
    [ "$code" -ne 0 ] || return 0
    [ "$code" -eq 3 ] || return 1
    row=$(json asset "$metadata" "$sums") || return 1
    IFS='|' read -r url _ <<< "$row"
    http "$url" "$dest.sums" || return 1
    hash=$(checksum_from_file "$dest.sums" "$name")
    # Miniforge also publishes a one-line digest without a filename.
    if [ -z "$hash" ] && [ "$(wc -l < "$dest.sums" | tr -d ' ')" -le 1 ]; then hash=$(awk '{print $1}' "$dest.sums"); fi
    verify_sha "$dest" "$hash"
}
safe_tar() {
    local archive=$1 dest=$2 list="$SESSION/tar-list"
    /usr/bin/tar -tf "$archive" > "$list" 2>>"$ERROR_LOG" || return 1
    if grep -Eq '(^/|(^|/)\.\.(/|$))' "$list"; then return 1; fi
    mkdir -p "$dest" || return 1
    /usr/bin/tar -xf "$archive" -C "$dest" 2>>"$ERROR_LOG"
}
install_binary() {
    local file=$1 dest="$HOME/.local/bin/$COMMAND"
    /usr/bin/file "$file" | grep -Eq 'arm64|universal' || return 1
    chmod 755 "$file" || return 1
    local downloaded_version
    if [ "$ADAPTER" = ncp ]; then downloaded_version=$(KUBECONFIG=/dev/null "$file" version 2>>"$ERROR_LOG" | extract_version);
    else downloaded_version=$("$file" --version 2>>"$ERROR_LOG" | extract_version); fi
    [ "$(normal_version "$downloaded_version")" = "$(normal_version "$TARGET")" ] || return 1
    mkdir -p "$HOME/.local/bin" || return 1
    if [ -e "$dest" ]; then cp -p "$dest" "$RUN_DIR/$ID.binary.backup" || return 1; fi
    cp "$file" "$dest.dev-setup-new" && chmod 755 "$dest.dev-setup-new" && mv "$dest.dev-setup-new" "$dest" || return 1
    printf '%s\n' "$TARGET" > "$STATE_ROOT/receipts/$ID"
}
install_brew_package() {
    local action=install resolved info
    [ -n "$BREW" ] || return 1
    # Refuse stale Homebrew metadata instead of implicitly updating Homebrew itself.
    info="$SESSION/$ID.local-brew.json"
    brew_cmd info --json=v2 "--$ADAPTER" "$PACKAGE" > "$info" 2>>"$ERROR_LOG" || return 1
    if [ "$ADAPTER" = formula ]; then
        resolved=$(json get "$info" formulae.0.versions.stable) || return 1
        local rev; rev=$(json get "$info" formulae.0.revision)
        [ "${rev:-0}" = 0 ] || resolved="${resolved}_$rev"
    else resolved=$(json get "$info" casks.0.version) || return 1; fi
    [ "$resolved" = "$TARGET" ] || return 1
    [ "$ACTION" != replace ] || action=upgrade
    if [ "$ADAPTER" = formula ]; then
        private_run brew_cmd fetch --formula --force-bottle --deps "$PACKAGE" || return 1
        private_run brew_cmd "$action" --formula --force-bottle "$PACKAGE"
    else
        private_run brew_cmd fetch --cask "$PACKAGE" || return 1
        # No --force, --zap, --greedy, --adopt or global upgrade.
        if [ "$action" = upgrade ]; then
            # Scoped --greedy includes this explicitly selected auto-updating cask.
            private_run brew_cmd upgrade --cask --greedy "$PACKAGE"
        else private_run brew_cmd install --cask "$PACKAGE"; fi
    fi
}
install_adapter() {
    local archive="$SESSION/$ID.download" stage="$SESSION/$ID.stage" v name url hash file row kubectl krew
    case "$ADAPTER" in
        formula|cask) install_brew_package;;
        brew_bootstrap)
            if [ "$ACTION" = replace ]; then private_run brew_cmd update; return; fi
            http 'https://api.github.com/repos/Homebrew/install/commits/HEAD' "$SESSION/brew-install.json" || return 1
            v=$(json get "$SESSION/brew-install.json" sha) || return 1
            [[ "$v" =~ ^[a-f0-9]{40}$ ]] || return 1
            http "https://raw.githubusercontent.com/Homebrew/install/$v/install.sh" "$archive" || return 1
            /bin/bash -n "$archive" || return 1
            # Interactive sudo remains attached to the user's terminal.
            printf 'Homebrew 공식 설치 프로그램의 관리자 인증·계속 진행 안내를 따라주세요.\n'
            /bin/bash "$archive" || return 1
            BREW=$(find_command brew) || return 1;;
        nvm|omz)
            if [ "$ADAPTER" = nvm ]; then v="v$TARGET"; else v=$TARGET; fi
            http "https://api.github.com/repos/$UPSTREAM/tarball/$v" "$archive" || return 1
            safe_tar "$archive" "$stage" || return 1
            file=$(find "$stage" -mindepth 1 -maxdepth 1 -type d | head -1)
            [ -n "$file" ] || return 1
            if [ "$ADAPTER" = nvm ]; then
                /bin/bash -n "$file/nvm.sh" || return 1
                v=$(/bin/bash -c '. "$1" --no-use; nvm --version' bash "$file/nvm.sh") || return 1
                [ "$v" = "$TARGET" ] || return 1
                mv "$file" "${NVM_DIR:-$HOME/.nvm}" || return 1
                printf '%s\n' "$TARGET" > "${NVM_DIR:-$HOME/.nvm}/.dev-setup-version"
            else
                [ -f "$file/oh-my-zsh.sh" ] || return 1
                mv "$file" "${ZSH:-$HOME/.oh-my-zsh}" || return 1
                printf '%s\n' "$TARGET" > "${ZSH:-$HOME/.oh-my-zsh}/.dev-setup-version"
            fi;;
        mamba)
            v=$(json release "$META") || return 1
            name="Miniforge3-${v}-MacOSX-arm64.sh"
            asset_with_checksum "$META" "$name" "$name.sha256" "$archive" || return 1
            private_run /bin/bash "$archive" -b -p "$HOME/miniforge3" || return 1
            # This prefix was just created; never run this on an existing base.
            private_run "$HOME/miniforge3/bin/conda" install --yes --name base --freeze-installed --override-channels --channel conda-forge "mamba=$TARGET" || return 1
            private_run "$HOME/miniforge3/bin/conda" config --file "$HOME/miniforge3/.condarc" --set auto_activate_base false;;
        krew)
            name=krew-darwin_arm64.tar.gz
            asset_with_checksum "$META" "$name" "$name.sha256" "$archive" || return 1
            safe_tar "$archive" "$stage" || return 1
            file=$(find "$stage" -type f -name krew-darwin_arm64 | head -1)
            [ -n "$file" ] || return 1
            chmod +x "$file" || return 1
            if [ "$ACTION" = replace ]; then
                krew=$(find_command kubectl-krew) || return 1
                private_run env KUBECONFIG=/dev/null "$krew" update && private_run env KUBECONFIG=/dev/null "$krew" upgrade krew
            else private_run env KUBECONFIG=/dev/null "$file" install krew; fi;;
        cnpg)
            kubectl=$(find_command kubectl) || return 1
            # Refresh only index metadata; never upgrade all plugins or Krew itself.
            private_run env KUBECONFIG=/dev/null PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" "$kubectl" krew update || return 1
            file="${KREW_ROOT:-$HOME/.krew}/index/default/plugins/cnpg.yaml"
            [ -f "$file" ] || return 1
            v=$(awk '/^  version:/{gsub(/["\047]/,"",$2);sub(/^v/,"",$2);print $2}' "$file")
            [ "$v" = "$TARGET" ] || return 1
            if [ "$ACTION" = replace ]; then v=upgrade; else v=install; fi
            private_run env KUBECONFIG=/dev/null PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH" "$kubectl" krew "$v" cnpg;;
        ncp)
            name=ncp-iam-authenticator_darwin_arm64
            asset_with_checksum "$META" "$name" "ncp-iam-authenticator_${TARGET}_SHA256SUMS" "$archive" || return 1
            install_binary "$archive";;
        terraform)
            name="terraform_${TARGET}_darwin_arm64.zip"
            url="https://releases.hashicorp.com/terraform/$TARGET"
            http "$url/$name" "$archive" && http "$url/terraform_${TARGET}_SHA256SUMS" "$archive.sums" || return 1
            hash=$(checksum_from_file "$archive.sums" "$name")
            verify_sha "$archive" "$hash" || return 1
            mkdir -p "$stage" || return 1
            private_run /usr/bin/unzip -j "$archive" terraform -d "$stage" || return 1
            install_binary "$stage/terraform";;
        orca|cua_app|dmg_app)
            if [ "$ADAPTER" != cua_app ]; then
                if [ "$ADAPTER" = orca ]; then
                    name=orca-macos-arm64.dmg
                    download_asset "$META" "$name" "$archive" || return 1
                else
                    url=$(json get "$META" url); hash=$(json get "$META" sha256)
                    # Only the vendor DMG is used; no cask postflight/symlink script runs.
                    http "$url" "$archive" && verify_sha "$archive" "$hash" || return 1
                fi
                mkdir -p "$stage" || return 1
                private_run /usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$stage" "$archive" || return 1
                MOUNTED_VOLUME=$stage
                install_app_bundle "$stage/$APP"; v=$?
                private_run /usr/bin/hdiutil detach "$stage" || return 1
                MOUNTED_VOLUME=
                return "$v"
            else
                name=$(json arm-asset "$META") || return 1
                asset_with_checksum "$META" "$name" checksums.txt "$archive" || return 1
                safe_tar "$archive" "$stage" || return 1
                file=$(find "$stage" -type d -name "$APP" -prune | head -1)
                [ -n "$file" ] || return 1
                install_app_bundle "$file"
            fi;;
        *) return 1;;
    esac
}

install_app_bundle() {
    local source=$1 dest="$HOME/Applications/$APP" staged="$HOME/Applications/$APP.dev-setup-new" minimum executable
    bundle_matches "$(plist "$source" CFBundleIdentifier)" || return 1
    [ "$(normal_version "$(plist "$source" CFBundleShortVersionString)")" = "$(normal_version "$TARGET")" ] || return 1
    minimum=$(plist "$source" LSMinimumSystemVersion) || minimum=
    [ -z "$minimum" ] || version_ge "$MACOS_VERSION" "$minimum" || return 1
    executable=$(plist "$source" CFBundleExecutable) || return 1
    case "$executable" in */*|''|..|.) return 1;; esac
    /usr/bin/file "$source/Contents/MacOS/$executable" | grep -q arm64 || return 1
    private_run /usr/bin/codesign --verify --deep --strict "$source" || return 1
    private_run /usr/sbin/spctl --assess --type execute "$source" || return 1
    if /usr/bin/pgrep -f "$dest/Contents/MacOS/" >/dev/null; then return 1; fi
    [ ! -e "$staged" ] || return 1
    mkdir -p "$HOME/Applications" || return 1
    private_run /usr/bin/ditto "$source" "$staged" || return 1
    if [ -e "$dest" ]; then mv "$dest" "$RUN_DIR/$APP.backup" || return 1; fi
    if ! mv "$staged" "$dest"; then
        [ ! -e "$RUN_DIR/$APP.backup" ] || mv "$RUN_DIR/$APP.backup" "$dest"
        return 1
    fi
    printf '%s\n' "$TARGET" > "$STATE_ROOT/receipts/$ID"
    # Installing the app never launches its daemon, imports settings, or adds skills.
}
