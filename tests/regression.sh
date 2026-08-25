#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  haystack=$1
  needle=$2
  label=$3

  case "$haystack" in
    *"$needle"*) ;;
    *) fail "$label (missing: $needle)" ;;
  esac
}

assert_status() {
  actual=$1
  expected=$2
  label=$3

  if [ "$actual" -ne "$expected" ]; then
    fail "$label (expected $expected, got $actual)"
  fi
}

run_pkg_maint() {
  output_file=$1
  shift

  set +e
  "$REPO_ROOT/bin/pkg-maint" "$@" >"$output_file" 2>&1
  status=$?
  set -e
  return "$status"
}

test_help_and_syntax() {
  sh -n "$REPO_ROOT/bin/pkg-maint"

  output_file=$(mktemp "${TMPDIR:-/tmp}/pkg-maint-test-help.XXXXXX")
  if run_pkg_maint "$output_file" --help; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")
  rm -f "$output_file"

  assert_status "$status" 0 "help exits successfully"
  assert_contains "$output" "<pip|uv|npm|all>" "help advertises uv manager"
  assert_contains "$output" "--migrate-nvm" "help advertises automatic NVM migration"
  assert_contains "$output" "--migrate-nvm-from" "help advertises explicit NVM source selection"
}

test_pip_npm_check_mode() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-pipnpm.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  cat >"$tmpdir/fakepip" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "list" ]; then
  printf '[{"name":"alpha","version":"1.0.0","latest_version":"1.2.0"},{"name":"holdme","version":"0.1","latest_version":"0.2"}]\n'
  exit 0
fi
if [ "$1" = "install" ]; then
  exit 0
fi
exit 1
EOF

  cat >"$tmpdir/fakenpm" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "outdated" ]; then
  printf '{"beta":{"current":"2.0.0","latest":"2.1.0"}}\n'
  exit 1
fi
if [ "$1" = "install" ]; then
  exit 0
fi
exit 1
EOF

  cat >"$tmpdir/fakeuv" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "tool" ] && [ "$2" = "list" ]; then
  printf 'No tools installed\n'
  exit 0
fi
exit 1
EOF

  chmod +x "$tmpdir/fakepip" "$tmpdir/fakenpm" "$tmpdir/fakeuv"

  cat >"$tmpdir/config.env" <<EOF
PIP_CMD="$tmpdir/fakepip"
UV_CMD="$tmpdir/fakeuv"
NPM_CMD="$tmpdir/fakenpm"
PIP_EXCLUDE="holdme"
LOG_FILE="$tmpdir/history.log"
EOF

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --check --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")

  assert_status "$status" 2 "check mode returns 2 when updates exist"
  assert_contains "$output" "pip      alpha" "pip update is listed"
  assert_contains "$output" "pip      holdme" "held pip package is listed"
  assert_contains "$output" "held" "held action is shown"
  assert_contains "$output" "npm      beta" "npm update is listed"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_uv_check_mode() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-uvcheck.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  mkdir -p "$tmpdir/tools/ruff/bin" "$tmpdir/tools/holdtool/bin" "$tmpdir/tools/uptodate/bin"

  cat >"$tmpdir/fakeuv" <<EOF
#!/usr/bin/env sh
cmd=\$1
sub=\$2
case "\$cmd \$sub" in
  "tool list")
    printf 'ruff\nholdtool\nuptodate\n'
    ;;
  "tool dir")
    printf '%s\n' "$tmpdir/tools"
    ;;
  "tool upgrade")
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF

  cat >"$tmpdir/tools/ruff/bin/python" <<'EOF'
#!/usr/bin/env sh
printf '[{"name":"ruff","version":"0.6.1","latest_version":"0.6.3"}]\n'
EOF

  cat >"$tmpdir/tools/holdtool/bin/python" <<'EOF'
#!/usr/bin/env sh
printf '[{"name":"holdtool","version":"1.0","latest_version":"1.1"}]\n'
EOF

  cat >"$tmpdir/tools/uptodate/bin/python" <<'EOF'
#!/usr/bin/env sh
printf '[]\n'
EOF

  chmod +x \
    "$tmpdir/fakeuv" \
    "$tmpdir/tools/ruff/bin/python" \
    "$tmpdir/tools/holdtool/bin/python" \
    "$tmpdir/tools/uptodate/bin/python"

  cat >"$tmpdir/config.env" <<EOF
UV_CMD="$tmpdir/fakeuv"
UV_EXCLUDE="holdtool"
PIP_CMD="nonexistent-pip"
NPM_CMD="nonexistent-npm"
LOG_FILE="$tmpdir/history.log"
EOF

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --check --manager uv --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")

  assert_status "$status" 2 "uv check mode returns 2 when updates exist"
  assert_contains "$output" "uv       ruff" "uv update is listed"
  assert_contains "$output" "uv       holdtool" "held uv tool is listed"
  assert_contains "$output" "held" "uv held action is shown"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_uv_install_failure() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-uvinstall.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  mkdir -p "$tmpdir/tools/ruff/bin" "$tmpdir/tools/badtool/bin"

  cat >"$tmpdir/fakeuv" <<EOF
#!/usr/bin/env sh
cmd=\$1
sub=\$2
case "\$cmd \$sub" in
  "tool list")
    printf 'ruff\nbadtool\n'
    ;;
  "tool dir")
    printf '%s\n' "$tmpdir/tools"
    ;;
  "tool upgrade")
    pkg=\$3
    if [ "\$pkg" = "badtool" ]; then
      printf 'permission denied\n' >&2
      exit 13
    fi
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
EOF

  cat >"$tmpdir/tools/ruff/bin/python" <<'EOF'
#!/usr/bin/env sh
printf '[{"name":"ruff","version":"0.6.1","latest_version":"0.6.3"}]\n'
EOF

  cat >"$tmpdir/tools/badtool/bin/python" <<'EOF'
#!/usr/bin/env sh
printf '[{"name":"badtool","version":"1.0","latest_version":"1.1"}]\n'
EOF

  chmod +x \
    "$tmpdir/fakeuv" \
    "$tmpdir/tools/ruff/bin/python" \
    "$tmpdir/tools/badtool/bin/python"

  cat >"$tmpdir/config.env" <<EOF
UV_CMD="$tmpdir/fakeuv"
PIP_CMD="nonexistent-pip"
NPM_CMD="nonexistent-npm"
LOG_FILE="$tmpdir/history.log"
EOF

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --yes --manager uv --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")

  assert_status "$status" 1 "uv install failure returns 1"
  assert_contains "$output" "updated=1 failed=1" "uv summary tracks failed installs"
  assert_contains "$output" "uv/badtool" "failure details include the tool name"

  history_lines=$(wc -l <"$tmpdir/history.log" | tr -d ' ')
  assert_status "$history_lines" 5 "history log records run, scan, installs, and finish"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_npm_nvm_detection_verbose_and_run_logging() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-nvm.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  active_prefix="$tmpdir/nvm/versions/node/v2"
  inactive_prefix="$tmpdir/nvm/versions/node/v1"
  mkdir -p \
    "$active_prefix/lib/node_modules/npm" \
    "$inactive_prefix/lib/node_modules/npm" \
    "$inactive_prefix/lib/node_modules/@openai/codex"

  printf '{"name":"npm","version":"2.0.0"}\n' >"$active_prefix/lib/node_modules/npm/package.json"
  printf '{"name":"npm","version":"1.0.0"}\n' >"$inactive_prefix/lib/node_modules/npm/package.json"
  printf '{"name":"@openai/codex","version":"0.1.0"}\n' >"$inactive_prefix/lib/node_modules/@openai/codex/package.json"

  cat >"$tmpdir/fakenpm" <<EOF
#!/usr/bin/env sh
if [ "\$1 \$2 \$3" = "config get prefix" ]; then
  printf '%s\n' "$active_prefix"
  exit 0
fi
if [ "\$1" = "outdated" ]; then
  printf '{}\n'
  exit 0
fi
exit 1
EOF
  chmod +x "$tmpdir/fakenpm"

  cat >"$tmpdir/config.env" <<EOF
NVM_DIR="$tmpdir/nvm"
NPM_CMD="$tmpdir/fakenpm"
LOG_FILE="$tmpdir/history.log"
EOF

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --check --manager npm --verbose --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")
  history=$(cat "$tmpdir/history.log")

  assert_status "$status" 0 "clean npm scan succeeds"
  assert_contains "$output" "npm active prefix: $active_prefix (global packages=1)" "verbose output identifies active npm prefix"
  assert_contains "$output" "inactive NVM prefix v1" "inactive NVM prefix is reported"
  assert_contains "$output" "@openai/codex" "inactive package name is reported"
  assert_contains "$output" "npm scan complete: packages=1 outdated=0" "verbose output includes npm scan count"
  assert_contains "$output" "selected non-APT manager(s): npm" "no-update output states non-APT scope"
  assert_contains "$history" "start mode=check manager=npm" "history records run start"
  assert_contains "$history" "status=ok prefix=$active_prefix packages=1 outdated=0 inactive_nvm_prefixes=1" "history records npm scan context"
  assert_contains "$history" "finish outcome=no-updates rc=0" "history records run completion"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_unavailable_manager_is_scan_failure() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-unavailable.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  cat >"$tmpdir/config.env" <<EOF
PIP_CMD="pkg-maint-command-that-does-not-exist"
LOG_FILE="$tmpdir/history.log"
EOF

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --check --manager pip --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")

  assert_status "$status" 1 "unavailable selected manager fails the scan"
  assert_contains "$output" "pip manager unavailable" "unavailable manager is reported"
  assert_contains "$output" "no selected package managers are available" "unavailable-only scan does not claim a clean result"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_uv_partial_scan_failure_propagates() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-uvscanfail.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  mkdir -p "$tmpdir/tools/broken/bin"
  cat >"$tmpdir/fakeuv" <<EOF
#!/usr/bin/env sh
if [ "\$1 \$2" = "tool list" ]; then
  printf 'broken\n'
  exit 0
fi
if [ "\$1 \$2" = "tool dir" ]; then
  printf '%s\n' "$tmpdir/tools"
  exit 0
fi
exit 1
EOF
  cat >"$tmpdir/tools/broken/bin/python" <<'EOF'
#!/usr/bin/env sh
printf 'registry unavailable\n' >&2
exit 1
EOF
  chmod +x "$tmpdir/fakeuv" "$tmpdir/tools/broken/bin/python"

  cat >"$tmpdir/config.env" <<EOF
UV_CMD="$tmpdir/fakeuv"
LOG_FILE="$tmpdir/history.log"
EOF

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --check --manager uv --verbose --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")

  assert_status "$status" 1 "failed uv sub-scan propagates failure"
  assert_contains "$output" "uv tool scan failed for broken" "failed uv tool is identified"
  assert_contains "$output" "No updates confirmed" "failed uv sub-scan does not claim a clean result"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_log_write_failure_is_visible() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-logfail.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  printf 'not a directory\n' >"$tmpdir/notdir"
  cat >"$tmpdir/fakenpm" <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "outdated" ]; then
  printf '{}\n'
  exit 0
fi
exit 1
EOF
  chmod +x "$tmpdir/fakenpm"

  cat >"$tmpdir/config.env" <<EOF
NVM_DIR="$tmpdir/nvm"
NPM_CMD="$tmpdir/fakenpm"
LOG_FILE="$tmpdir/notdir/history.log"
EOF

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --check --manager npm --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")

  assert_status "$status" 0 "log failure does not block a successful scan"
  assert_contains "$output" "unable to write history log" "log write failure is visible"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_nvm_migration_preview_and_install() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-migrate.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  active_prefix="$tmpdir/nvm/versions/node/v2"
  inactive_prefix="$tmpdir/nvm/versions/node/v1"
  mkdir -p \
    "$active_prefix/lib/node_modules/npm" \
    "$inactive_prefix/lib/node_modules/npm" \
    "$inactive_prefix/lib/node_modules/@openai/codex"
  printf '{"name":"npm","version":"2.0.0"}\n' >"$active_prefix/lib/node_modules/npm/package.json"
  printf '{"name":"npm","version":"1.0.0"}\n' >"$inactive_prefix/lib/node_modules/npm/package.json"
  printf '{"name":"@openai/codex","version":"0.1.0"}\n' >"$inactive_prefix/lib/node_modules/@openai/codex/package.json"

  cat >"$tmpdir/fakenpm" <<EOF
#!/usr/bin/env sh
if [ "\$1 \$2 \$3" = "config get prefix" ]; then
  printf '%s\n' "$active_prefix"
  exit 0
fi
if [ "\$1" = "outdated" ]; then
  printf '{}\n'
  exit 0
fi
if [ "\$1 \$2" = "install -g" ]; then
  spec=\$3
  name=\${spec%@*}
  version=\${spec##*@}
  mkdir -p "$active_prefix/lib/node_modules/\$name"
  printf '{"name":"%s","version":"%s"}\n' "\$name" "\$version" >"$active_prefix/lib/node_modules/\$name/package.json"
  exit 0
fi
exit 1
EOF
  chmod +x "$tmpdir/fakenpm"

  cat >"$tmpdir/config.env" <<EOF
NVM_DIR="$tmpdir/nvm"
NPM_CMD="$tmpdir/fakenpm"
PIP_CMD="pkg-maint-migration-missing-pip"
UV_CMD="pkg-maint-migration-missing-uv"
LOG_FILE="$tmpdir/history.log"
EOF

  preview_output="$tmpdir/preview.txt"
  if run_pkg_maint "$preview_output" --migrate-nvm --check --manager npm --config "$tmpdir/config.env"; then
    preview_status=0
  else
    preview_status=$?
  fi
  preview=$(cat "$preview_output")

  assert_status "$preview_status" 2 "migration preview reports available action"
  assert_contains "$preview" "NVM package migration preview" "migration preview is shown"
  assert_contains "$preview" "Source: v1" "single source is selected automatically"
  assert_contains "$preview" "Active target: $active_prefix" "active target is shown"
  assert_contains "$preview" "@openai/codex" "migration package is listed"
  if [ -e "$active_prefix/lib/node_modules/@openai/codex/package.json" ]; then
    fail "migration preview modified the active prefix"
  fi

  migrate_output="$tmpdir/migrate.txt"
  if run_pkg_maint "$migrate_output" --migrate-nvm --yes --manager npm --config "$tmpdir/config.env"; then
    migrate_status=0
  else
    migrate_status=$?
  fi
  migrated=$(cat "$migrate_output")
  history=$(cat "$tmpdir/history.log")
  tab_char=$(printf '\t')

  assert_status "$migrate_status" 0 "automatic migration succeeds for one source"
  assert_contains "$migrated" "Migrating @openai/codex (0.1.0)" "migration action is shown"
  assert_contains "$migrated" "requested=1 migrated=1 failed=0" "migration summary is accurate"
  assert_contains "$history" "status=preview packages=1" "history records migration preview"
  assert_contains "$history" "migration${tab_char}@openai/codex${tab_char}v1${tab_char}0.1.0${tab_char}ok" "history records migrated package"
  assert_contains "$history" "status=complete migrated=1" "history records migration completion"
  if [ ! -e "$active_prefix/lib/node_modules/@openai/codex/package.json" ]; then
    fail "migrated package is missing from active prefix"
  fi
  if [ ! -e "$inactive_prefix/lib/node_modules/@openai/codex/package.json" ]; then
    fail "source package was removed during migration"
  fi

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

test_nvm_migration_yes_rejects_ambiguous_sources() {
  tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/pkg-maint-test-migrate-many.XXXXXX")
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  active_prefix="$tmpdir/nvm/versions/node/v3"
  mkdir -p \
    "$active_prefix/lib/node_modules/npm" \
    "$tmpdir/nvm/versions/node/v1/lib/node_modules/alpha" \
    "$tmpdir/nvm/versions/node/v2/lib/node_modules/beta"
  printf '{"name":"npm","version":"3.0.0"}\n' >"$active_prefix/lib/node_modules/npm/package.json"
  printf '{"name":"alpha","version":"1.0.0"}\n' >"$tmpdir/nvm/versions/node/v1/lib/node_modules/alpha/package.json"
  printf '{"name":"beta","version":"2.0.0"}\n' >"$tmpdir/nvm/versions/node/v2/lib/node_modules/beta/package.json"

  cat >"$tmpdir/fakenpm" <<EOF
#!/usr/bin/env sh
if [ "\$1 \$2 \$3" = "config get prefix" ]; then
  printf '%s\n' "$active_prefix"
  exit 0
fi
if [ "\$1" = "outdated" ]; then
  printf '{}\n'
  exit 0
fi
exit 1
EOF
  chmod +x "$tmpdir/fakenpm"
  cat >"$tmpdir/config.env" <<EOF
NVM_DIR="$tmpdir/nvm"
NPM_CMD="$tmpdir/fakenpm"
LOG_FILE="$tmpdir/history.log"
EOF

  preview_file="$tmpdir/preview.txt"
  if run_pkg_maint "$preview_file" --migrate-nvm-from 2 --check --manager npm --config "$tmpdir/config.env"; then
    preview_status=0
  else
    preview_status=$?
  fi
  preview=$(cat "$preview_file")

  assert_status "$preview_status" 2 "explicit migration source preview reports available action"
  assert_contains "$preview" "Source: v2" "source version accepts shorthand without v prefix"
  assert_contains "$preview" "beta" "selected source package is previewed"

  output_file="$tmpdir/output.txt"
  if run_pkg_maint "$output_file" --migrate-nvm --yes --manager npm --config "$tmpdir/config.env"; then
    status=0
  else
    status=$?
  fi
  output=$(cat "$output_file")

  assert_status "$status" 1 "automatic migration rejects ambiguous sources"
  assert_contains "$output" "Multiple inactive NVM environments" "ambiguous sources are listed"
  assert_contains "$output" "require --migrate-nvm-from" "explicit selection guidance is shown"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

main() {
  test_help_and_syntax
  test_pip_npm_check_mode
  test_uv_check_mode
  test_uv_install_failure
  test_npm_nvm_detection_verbose_and_run_logging
  test_unavailable_manager_is_scan_failure
  test_uv_partial_scan_failure_propagates
  test_log_write_failure_is_visible
  test_nvm_migration_preview_and_install
  test_nvm_migration_yes_rejects_ambiguous_sources
  printf 'All regression tests passed.\n'
}

main "$@"
