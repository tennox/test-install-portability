#!/usr/bin/env bash
set -euo pipefail

echo "=== install stdin portability tests ==="
echo "Running on: $(uname -a)"
echo

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

pass=0
fail=0

record_pass() {
  pass=$((pass + 1))
  printf '[PASS] %s\n' "$1"
}

record_fail() {
  fail=$((fail + 1))
  printf '[FAIL] %s\n' "$1"
}

run_test() {
  local name="$1"
  shift
  if "$@"; then
    record_pass "$name"
  else
    record_fail "$name"
  fi
}

check_script_runs() {
  # $1 = path, $2 = expected output
  local path="$1"
  local expected="$2"

  if [ ! -x "$path" ]; then
    echo "  Script is not executable: $path"
    return 1
  fi

  local output
  if ! output="$("$path")"; then
    echo "  Script failed to run: $path"
    return 1
  fi

  if [ "$output" != "$expected" ]; then
    echo "  Unexpected output"
    echo "    got : $output"
    echo "    want: $expected"
    return 1
  fi

  return 0
}

prepare_foreign_file() {
  # Create a file owned by root, but world-writable, in a directory owned by us.
  # This mimics “we can write to the file but cannot chmod it”.
  local path="$1"
  local dir
  dir="$(dirname "$path")"

  if ! command -v sudo >/dev/null 2>&1; then
    echo "  [SKIP] sudo not available; cannot create foreign-owned file."
    return 1
  fi

  if ! sudo -n true >/dev/null 2>&1; then
    echo "  [SKIP] sudo requires a password; cannot create foreign-owned file."
    return 1
  fi

  mkdir -p "$dir"
  # Create the file as root with mode 666, owner root (group left as default).
  sudo sh -c "echo '# original content' >'$path'; chmod 666 '$path'; chown root '$path'"

  echo "  Created foreign-owned file:"
  ls -l "$path" || true

  return 0
}


test_install_stdin_heredoc() {
  # Variant:
  #   install -m 755 /dev/stdin target <<'EOF'
  local target="$tmpdir/stdin-heredoc.sh"

  install -m 755 /dev/stdin "$target" <<'EOF'
#!/usr/bin/env bash
echo "stdin heredoc"
EOF

  check_script_runs "$target" "stdin heredoc"
}

test_install_fd0_heredoc() {
  # Variant:
  #   install -m 755 /dev/fd/0 target <<'EOF'
  local target="$tmpdir/fd0-heredoc.sh"

  install -m 755 /dev/fd/0 "$target" <<'EOF'
#!/usr/bin/env bash
echo "fd0 heredoc"
EOF

  check_script_runs "$target" "fd0 heredoc"
}

test_cat_chmod() {
  # Classic portable alternative:
  #   cat >file <<EOF; chmod +x file
  local target="$tmpdir/cat-chmod.sh"

  cat >"$target" <<'EOF'
#!/usr/bin/env bash
echo "cat chmod"
EOF

  chmod 755 "$target"
  check_script_runs "$target" "cat chmod"
}

test_install_stdin_pipe_info() {
  # Informational test: echo | install -m 755 /dev/stdin target
  # Not treated as pass/fail, just report behaviour.
  local target="$tmpdir/stdin-pipe.sh"

  echo 'echo "stdin pipe"' | install -m 755 /dev/stdin "$target" >/dev/null 2>&1 && rc=0 || rc=$?

  if [ "$rc" -eq 0 ]; then
    echo "[INFO] echo | install -m 755 /dev/stdin succeeded on this platform"
    if check_script_runs "$target" "stdin pipe"; then
      echo "       Installed script runs and prints expected output."
    else
      echo "       Installed script did not behave as expected."
    fi
  else
    echo "[INFO] echo | install -m 755 /dev/stdin failed with status $rc on this platform"
  fi

  return 0
}

test_cat_chmod_foreign_owner() {
  # Demonstrate why cat+chmod is broken when file is owned by another user.
  local target="$tmpdir/foreign/cat-chmod-foreign.sh"

  if ! prepare_foreign_file "$target"; then
    echo "  Skipping test_cat_chmod_foreign_owner."
    return 0
  fi

  echo "  Writing new content via cat > (should succeed; file is mode 666)"
  if ! cat >"$target" <<'EOF'
#!/usr/bin/env bash
echo "cat chmod foreign owner"
EOF
  then
    echo "  cat >'$target' failed unexpectedly"
    return 1
  fi

  echo "  Running chmod 755 on foreign-owned file (should fail)"
  if chmod 755 "$target" 2>/dev/null; then
    echo "  chmod unexpectedly succeeded on foreign-owned file"
    return 1
  fi

  echo "  chmod failed as expected on foreign-owned file (ownership check)"
  return 0
}

test_install_stdin_heredoc_foreign_owner() {
  # This is the pattern from your fix:
  #   install -m 755 /dev/stdin target <<'EOF'
  # It should succeed even when the previous file was owned by root, as long as
  # we have write permission on the directory.
  local target="$tmpdir/foreign/install-stdin-foreign.sh"

  if ! prepare_foreign_file "$target"; then
    echo "  Skipping test_install_stdin_heredoc_foreign_owner."
    return 0
  fi

  echo "  Replacing foreign-owned file using install -m 755 /dev/stdin <<EOF"

  install -m 755 /dev/stdin "$target" <<'EOF'
#!/usr/bin/env bash
echo "install stdin foreign owner"
EOF

  ls -l "$target" || true

  check_script_runs "$target" "install stdin foreign owner"
}

echo "Using install at: $(command -v install || echo 'not found')"
echo

# Basic variants (no owner tricks)
run_test "install with /dev/stdin + heredoc"          test_install_stdin_heredoc
run_test "install with /dev/fd/0 + heredoc"           test_install_fd0_heredoc
run_test "cat >file + chmod 755 (baseline)"           test_cat_chmod

echo
# Foreign-owner scenario that motivated the change
run_test "cat >file + chmod 755 on foreign-owned file (chmod must fail)" \
         test_cat_chmod_foreign_owner
run_test "install -m 755 /dev/stdin on foreign-owned file (must succeed)" \
         test_install_stdin_heredoc_foreign_owner

echo
test_install_stdin_pipe_info
echo

echo "=== Summary ==="
echo "  Passed: $pass"
echo "  Failed: $fail"

if [ "$fail" -ne 0 ]; then
  exit 1
fi

echo "All required portability tests passed."

