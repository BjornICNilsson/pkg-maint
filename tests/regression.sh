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

  chmod +x "$tmpdir/fakepip" "$tmpdir/fakenpm"

  cat >"$tmpdir/config.env" <<EOF
PIP_CMD="$tmpdir/fakepip"
UV_CMD="nonexistent-uv"
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
  assert_status "$history_lines" 2 "history log records both uv install attempts"

  rm -rf "$tmpdir"
  trap - EXIT INT TERM
}

main() {
  test_help_and_syntax
  test_pip_npm_check_mode
  test_uv_check_mode
  test_uv_install_failure
  printf 'All regression tests passed.\n'
}

main "$@"
