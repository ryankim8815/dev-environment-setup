#!/bin/bash
set -u
set -o pipefail
ROOT=$1
SANDBOX=$2
. "$ROOT/lib/core.sh"
. "$ROOT/lib/adapters.sh"
. "$ROOT/lib/settings.sh"
SESSION="$SANDBOX/session"
mkdir -p "$SESSION"
ERROR_LOG="$SESSION/errors.log"
STATE_ROOT="$HOME/Library/Application Support/dev-environment-setup"
RUN_DIR="$STATE_ROOT/runs/test"
mkdir -p "$RUN_DIR" "$STATE_ROOT/receipts"
MODE=apply BREW= OS_TAG=arm64_sequoia MACOS_VERSION=15.6 RUN_FAILED=0
TOTAL=0 FAILED=0
fail() { printf '  %s\n' "$*" >&2; exit 1; }
eq() { [ "$1" = "$2" ] || fail "expected [$2], got [$1]"; }
contains() { grep -Fq -- "$2" "$1" || fail "missing expected text: $2"; }
absent() { ! grep -Eq -- "$2" "$1" || fail "unexpected text: $2"; }
test_case() {
    TOTAL=$((TOTAL + 1))
    if ( "$@" ); then printf 'ok %s - %s\n' "$TOTAL" "$1";
    else printf 'not ok %s - %s\n' "$TOTAL" "$1"; FAILED=$((FAILED + 1)); fi
}
config() { printf '%s\n' "$1" > "$SESSION/input.json"; json config "$SESSION/input.json" "$ROOT/lib/catalog.tsv" > "$SESSION/config"; }
empty_config() { config '{"schema_version":1,"tools":{},"settings":{"shell_init":false}}'; }

test_config_defaults() {
    json config "$ROOT/config.example.json" "$ROOT/lib/catalog.tsv" > "$SESSION/config" || fail parse
    eq "$(config_value nvm 3)" true
    eq "$(config_value mamba 3)" true
    local t
    for t in kubectl helm k9s krew cnpg ncp_iam_authenticator docker terraform logcli; do eq "$(config_value "$t" 3)" false; done
}
test_config_inheritance() {
    config '{"schema_version":1,"defaults":{"reinstall_on_version_mismatch":true},"tools":{"helm":{"enabled":true,"reinstall_on_version_mismatch":false}}}' || fail config
    eq "$(config_value helm 4)" false
    eq "$(config_value kubectl 4)" true
    eq "$(config_value kubectl 3)" false
}
test_config_rejects_invalid() {
    local input
    for input in '{"schema_version":2}' '{"schema_version":1,"tools":{"helm":{"enabled":"false"}}}' \
        '{"schema_version":1,"tools":{"unknown":{"enabled":true}}}' '{"schema_version":1,"tools":null}' \
        '{"schema_version":1,"tools":{"helm":null}}' '{"schema_version":1,"settings":[]}' \
        '{"schema_version":1,"defaults":{"reinstall_on_version_mismatch":1}}' '{"schema_version":1,"oops":true}' \
        '{"schema_version":1,"extensions":{"vscode":["--force"]}}'; do
        if config "$input"; then fail 'invalid config accepted'; fi
    done
}
test_config_extensions() {
    config '{"schema_version":1,"extensions":{"vscode":["sample.extension","sample.extension"]}}' || fail config
    eq "$(grep -c '^extension|' "$SESSION/config")" 1
}

policy_setup() {
    config '{"schema_version":1,"tools":{"helm":{"enabled":true}}}' || fail config
    FAKE_PRESENT=true FAKE_CURRENT=1.0.0 FAKE_ORIGIN=homebrew
    : > "$SESSION/calls"
    detect() { PRESENT=$FAKE_PRESENT; CURRENT=$FAKE_CURRENT; ORIGIN=$FAKE_ORIGIN; BIN=/test/helm; }
    resolve_target() { TARGET=2.0.0; }
    dependencies_ok() { return 0; }
    preflight_adapter() { return 0; }
    install_adapter() { printf 'install %s\n' "$ID" >> "$SESSION/calls"; FAKE_PRESENT=true; FAKE_CURRENT=2.0.0; }
}
test_existing_kept() {
    policy_setup; process_tool helm
    eq "$(state helm)" 유지; eq "$(cat "$SESSION/calls")" ''
}
test_missing_installed() {
    policy_setup; FAKE_PRESENT=false FAKE_CURRENT=-; process_tool helm
    eq "$(state helm)" 완료; contains "$SESSION/calls" 'install helm'
}
test_reinstall_opt_in() {
    policy_setup
    config '{"schema_version":1,"tools":{"helm":{"enabled":true,"reinstall_on_version_mismatch":true}}}' || fail config
    process_tool helm; eq "$(state helm)" 완료
}
test_unknown_never_removed() {
    policy_setup; FAKE_CURRENT=unknown
    process_tool helm; eq "$(state helm)" 수동작업; eq "$(cat "$SESSION/calls")" ''
}
test_external_never_replaced() {
    policy_setup; FAKE_ORIGIN=unknown
    config '{"schema_version":1,"defaults":{"reinstall_on_version_mismatch":true},"tools":{"helm":{"enabled":true}}}' || fail config
    process_tool helm; eq "$(state helm)" 수동작업
}
test_no_lookup_on_disabled() {
    empty_config; detect() { fail 'disabled tool inspected'; }; resolve_target() { fail 'disabled tool queried'; }
    process_tool helm; eq "$(state helm)" 비활성화
}
test_download_failure_keeps_existing() {
    policy_setup; resolve_target() { return 1; }
    process_tool helm; eq "$(state helm)" 확인필요; eq "$(cat "$SESSION/calls")" ''
}
test_dry_run_no_install() {
    policy_setup; MODE=dry-run FAKE_PRESENT=false; process_tool helm
    eq "$(state helm)" 예정; eq "$(cat "$SESSION/calls")" ''
}
test_check_no_install() {
    policy_setup; MODE=check FAKE_PRESENT=false; process_tool helm
    eq "$(state helm)" 미설치; eq "$(cat "$SESSION/calls")" ''
}
test_failure_then_retry() {
    policy_setup; FAKE_PRESENT=false
    install_adapter() { return 1; }
    process_tool helm; eq "$(state helm)" 실패
    install_adapter() { FAKE_PRESENT=true; FAKE_CURRENT=2.0.0; }
    process_tool helm; eq "$(state helm)" 완료
}
test_new_version_verification() {
    policy_setup; FAKE_PRESENT=false
    install_adapter() { FAKE_PRESENT=true; FAKE_CURRENT=1.5.0; }
    process_tool helm; eq "$(state helm)" 실패
}
test_cnpg_dependencies() {
    config '{"schema_version":1,"tools":{"cnpg":{"enabled":true}}}' || fail config
    detect() { PRESENT=false; }
    tool cnpg
    if dependencies_ok; then fail 'missing dependencies accepted'; fi
    eq "$ID" cnpg; [[ "$REASON" == *tools.kubectl.enabled* ]] || fail reason
    # Existing prerequisites can be reused even when disabled.
    detect() { PRESENT=true; CURRENT=1.0.0; }
    dependencies_ok || fail 'existing disabled prerequisite rejected'
}
test_planned_dependency_modes() {
    detect() { PRESENT=false; }
    printf '예정\n' > "$SESSION/kubectl.status"
    MODE=dry-run; dependency_ready kubectl || fail planned
    MODE=check; if dependency_ready kubectl; then fail check; fi
    MODE=apply; if dependency_ready kubectl; then fail apply; fi
}
test_dependency_conflict() {
    BREW=/fake/brew
    http() { cp "$SESSION/formula.json" "$2"; }
    printf '{"versions":{"stable":"2.0.0"},"revision":0,"bottle":{"stable":{"files":{"arm64_sequoia":{}}}},"dependencies":[]}' > "$SESSION/formula.json"
    brew_cmd() { printf 'dependency-test 1.0.0\n'; }
    if brew_dependency_guard dependency-test; then fail 'dependency upgrade permitted'; fi
    contains "$SESSION/dependency-error" '기존 버전 변경'
}
test_formula_revision_preserved() { ADAPTER=formula; eq "$(normal_version v1.2.3_1)" 1.2.3_1; }
test_cask_build_comparison() { ADAPTER=cask; eq "$(normal_version 1.2.3,456)" 1.2.3; }
test_kubernetes_only_local_version() {
    empty_config
    local fake="$SESSION/version-cli" t
    cat > "$fake" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$TEST_CALLS"
case "$*" in
  'version --client --output=json') printf '{"clientVersion":{"gitVersion":"v1.2.3"}}\n';;
  'version --short'|'version') printf 'Version: 1.2.3\nGitTag: v1.2.3\n';;
  *) exit 99;;
esac
EOF
    chmod +x "$fake"
    TEST_CALLS="$SESSION/kubernetes-calls"; export TEST_CALLS; : > "$TEST_CALLS"
    find_command() { printf '%s' "$fake"; }
    for t in kubectl helm k9s krew cnpg ncp_iam_authenticator; do
        tool "$t"; detect; eq "$PRESENT" true; eq "$CURRENT" 1.2.3
    done
    eq "$(wc -l < "$TEST_CALLS" | tr -d ' ')" 6
    absent "$TEST_CALLS" '(^get |apply|create-kubeconfig|token|cluster-info|status)'
}
shell_setup() {
    config '{"schema_version":1,"tools":{"nvm":{"enabled":true}}}' || fail config
    printf '유지\n' > "$SESSION/nvm.status"
    MODE=apply RUN_FAILED=0
    printf '# user setting\nexport EXAMPLE_OPTION=yes\n' > "$HOME/.zshrc"
}
test_shell_backup_and_idempotence() {
    shell_setup; configure_shell
    contains "$RUN_DIR/zshrc.backup" 'EXAMPLE_OPTION=yes'
    cp "$HOME/.zshrc" "$SESSION/first-zshrc"
    configure_shell
    cmp -s "$SESSION/first-zshrc" "$HOME/.zshrc" || fail duplicate
    eq "$(grep -c '^# >>>' "$HOME/.zshrc")" 1
    contains "$HOME/.zshrc" 'EXAMPLE_OPTION=yes'
}
test_shell_dry_run_and_check() {
    shell_setup; cp "$HOME/.zshrc" "$SESSION/before-zshrc"
    MODE=dry-run; configure_shell
    MODE=check; configure_shell
    cmp -s "$SESSION/before-zshrc" "$HOME/.zshrc" || fail mutation
    eq "$RUN_FAILED" 1
}
test_disabled_shell_preserves_file() {
    shell_setup
    config '{"schema_version":1,"tools":{"nvm":{"enabled":true}},"settings":{"shell_init":false}}' || fail config
    cp "$HOME/.zshrc" "$SESSION/before-disabled"
    configure_shell; cmp -s "$SESSION/before-disabled" "$HOME/.zshrc" || fail mutation
}
test_disabled_tool_keeps_initialization() {
    shell_setup; configure_shell
    config '{"schema_version":1,"tools":{"oh_my_zsh":{"enabled":true}}}' || fail config
    printf '유지\n' > "$SESSION/oh_my_zsh.status"
    configure_shell
    contains "$HOME/.zshrc" 'source "$NVM_DIR/nvm.sh" --no-use'
    contains "$HOME/.zshrc" 'oh-my-zsh.sh'
}
test_malformed_shell_block_preserved() {
    shell_setup; printf '# >>> dev-environment-setup >>>\nkeep this\n' > "$HOME/.zshrc"
    configure_shell; contains "$HOME/.zshrc" 'keep this'; eq "$RUN_FAILED" 1
}
test_shell_nvm_does_not_activate() {
    mkdir -p "$HOME/.nvm"
    cat > "$HOME/.nvm/nvm.sh" <<'EOF'
[[ "$1" == --no-use ]] || return 99
nvm() { printf 'fixture-nvm\n'; }
EOF
    /bin/zsh -f -c 'source "$1"; nvm' zsh "$ROOT/templates/nvm.zsh" > "$SESSION/nvm-out" || fail shell
    contains "$SESSION/nvm-out" fixture-nvm
}
test_shell_mamba_no_base_activation() {
    mkdir -p "$HOME/miniforge3/bin"
    cat > "$HOME/miniforge3/bin/mamba" <<'EOF'
#!/bin/bash
test "$CONDA_AUTO_ACTIVATE_BASE" = false || exit 99
printf 'mamba() { printf "fixture-mamba\\n"; }\n'
EOF
    chmod +x "$HOME/miniforge3/bin/mamba"
    /bin/zsh -f -c 'source "$1"; mamba; test -z "${CONDA_DEFAULT_ENV:-}"' zsh "$ROOT/templates/mamba.zsh" > "$SESSION/mamba-out" || fail shell
    contains "$SESSION/mamba-out" fixture-mamba
}
test_checksum_rejects_corruption() {
    printf 'fixture' > "$SESSION/payload"
    local hash; hash=$(/usr/bin/shasum -a 256 "$SESSION/payload" | awk '{print $1}')
    verify_sha "$SESSION/payload" "$hash" || fail checksum
    printf 'changed' >> "$SESSION/payload"
    if verify_sha "$SESSION/payload" "$hash"; then fail corruption; fi
}
test_homebrew_scoped_upgrade() {
    tool helm; ACTION=replace TARGET=2.0.0 BREW=/fake/brew
    : > "$SESSION/brew-commands"
    brew_cmd() {
        printf '%s\n' "$*" >> "$SESSION/brew-commands"
        if [ "$1" = info ]; then printf '{"formulae":[{"versions":{"stable":"2.0.0"},"revision":0}]}'; fi
    }
    install_brew_package || fail install
    contains "$SESSION/brew-commands" 'fetch --formula --force-bottle --deps helm'
    contains "$SESSION/brew-commands" 'upgrade --formula --force-bottle helm'
    absent "$SESSION/brew-commands" '^(update|upgrade$|uninstall|cleanup|bundle)'
}
test_stale_homebrew_metadata_blocks_mutation() {
    tool helm; ACTION=replace TARGET=2.0.0 BREW=/fake/brew
    brew_cmd() {
        [ "$1" = info ] || fail 'stale metadata reached mutation'
        printf '{"formulae":[{"versions":{"stable":"1.0.0"},"revision":0}]}'
    }
    if install_brew_package; then fail stale; fi
}
test_cnpg_scoped_upgrade() {
    tool cnpg; ACTION=replace TARGET=2.0.0
    KREW_ROOT="$SESSION/test-krew"
    mkdir -p "$KREW_ROOT/index/default/plugins"
    printf 'spec:\n  version: v2.0.0\n' > "$KREW_ROOT/index/default/plugins/cnpg.yaml"
    local cli="$SESSION/kubectl-stub"
    cat > "$cli" <<'EOF'
#!/bin/bash
test "$KUBECONFIG" = /dev/null || exit 99
printf '%s\n' "$*" >> "$TEST_CALLS"
EOF
    chmod +x "$cli"
    TEST_CALLS="$SESSION/krew-commands"; export TEST_CALLS; : > "$TEST_CALLS"
    find_command() { printf '%s' "$cli"; }
    install_adapter || fail krew
    contains "$TEST_CALLS" 'krew update'
    contains "$TEST_CALLS" 'krew upgrade cnpg'
    absent "$TEST_CALLS" 'krew upgrade$|get |apply |token|status'
}
test_release_rejects_prerelease() {
    printf '{"tag_name":"v2.0.0","prerelease":true,"draft":false}' > "$SESSION/release.json"
    if json release "$SESSION/release.json"; then fail prerelease; fi
}
test_cua_selects_product_stable() {
    printf '[{"tag_name":"sandbox-v9.0.0"},{"tag_name":"cua-driver-rs-v1.2.0","prerelease":true},{"tag_name":"cua-driver-rs-v1.3.0-nightly.1"},{"tag_name":"cua-driver-rs-v1.1.0"}]' > "$SESSION/cua.json"
    json cua-release "$SESSION/cua.json" > "$SESSION/cua-selected.json" || fail cua
    eq "$(json get "$SESSION/cua-selected.json" tag_name)" cua-driver-rs-v1.2.0
}
test_cask_unknown_hooks_blocked() {
    printf '{"version":"1.0.0","artifacts":[{"postflight_steps":[{}]}]}' > "$SESSION/cask.json"
    json brew "$SESSION/cask.json" cask arm64_sequoia > "$SESSION/cask.tsv" || fail cask
    contains "$SESSION/cask.tsv" 'unsupported|postflight_steps'
}
test_renamed_app_detection() {
    tool chatgpt; APP=ExpectedFixture.app; BUNDLE=org.example.fixture
    local app="$HOME/Applications/RenamedFixture.app"
    mkdir -p "$app/Contents"
    cat > "$app/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>org.example.fixture</string><key>CFBundleShortVersionString</key><string>1.2.3</string></dict></plist>
EOF
    detect; eq "$PRESENT" true; eq "$CURRENT" 1.2.3; eq "$FOUND_APP" "$app"
}
test_broken_version_is_unknown() {
    tool helm
    local cli="$SESSION/broken-version"
    printf '#!/bin/bash\nprintf "Version 1.2.3\\n"\nexit 1\n' > "$cli"; chmod +x "$cli"
    find_command() { printf '%s' "$cli"; }
    detect; eq "$PRESENT" true; eq "$CURRENT" unknown
}
test_all_disabled_entrypoints() {
    printf '{"schema_version":1,"tools":{}}\n' > "$SESSION/disabled.json"
    /bin/bash "$ROOT/setup.sh" --config "$SESSION/disabled.json" --dry-run > "$SESSION/dry-report" || fail dry
    /bin/bash "$ROOT/setup.sh" --config "$SESSION/disabled.json" --check > "$SESSION/check-report" || fail check
    /bin/bash "$ROOT/setup.sh" --config "$SESSION/disabled.json" > "$SESSION/apply-report" || fail apply
    contains "$SESSION/dry-report" '[Kubernetes]'
    contains "$SESSION/dry-report" '[컨테이너]'
    contains "$SESSION/dry-report" '[인프라 코드 관리]'
    contains "$SESSION/dry-report" '[로그·관측성]'
}
test_public_files() {
    if /usr/bin/grep -ERn '(/Users/[[:alnum:]_-]+/|nvm install|npm install -g|kubectl (get|apply|create)|create-kubeconfig)' "$ROOT/lib" "$ROOT/templates"; then fail public; fi
}

for test in test_config_defaults test_config_inheritance test_config_rejects_invalid test_config_extensions \
    test_existing_kept test_missing_installed test_reinstall_opt_in test_unknown_never_removed \
    test_external_never_replaced test_no_lookup_on_disabled test_download_failure_keeps_existing \
    test_dry_run_no_install test_check_no_install test_failure_then_retry test_new_version_verification \
    test_cnpg_dependencies test_planned_dependency_modes test_dependency_conflict \
    test_formula_revision_preserved test_cask_build_comparison test_kubernetes_only_local_version \
    test_shell_backup_and_idempotence test_shell_dry_run_and_check test_disabled_shell_preserves_file test_disabled_tool_keeps_initialization \
    test_malformed_shell_block_preserved test_shell_nvm_does_not_activate test_shell_mamba_no_base_activation \
    test_checksum_rejects_corruption test_homebrew_scoped_upgrade test_stale_homebrew_metadata_blocks_mutation \
    test_cnpg_scoped_upgrade test_release_rejects_prerelease test_cua_selects_product_stable test_cask_unknown_hooks_blocked \
    test_renamed_app_detection test_broken_version_is_unknown \
    test_all_disabled_entrypoints test_public_files; do test_case "$test"; done
printf '\n%s tests; %s failures\n' "$TOTAL" "$FAILED"
[ "$FAILED" -eq 0 ]
