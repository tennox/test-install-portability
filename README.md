# Install Stdin Portability Test Results

This repository tests different approaches for installing executable scripts using the `install(1)` command, with a focus on cross-platform portability between Linux (GNU coreutils) and macOS (BSD).

## Test Results

**Latest test run:** [GitHub Actions Workflow](https://github.com/tennox/test-install-portability/actions/runs/20151852415)

### Summary

All required portability tests **PASSED** on both Linux and macOS.

| Test | Linux (Ubuntu 24.04) | macOS (Darwin 24.6) |
|------|---------------------|---------------------|
| `install -m 755 /dev/stdin <<EOF` | ✅ PASS | ✅ PASS |
| `install -m 755 /dev/fd/0 <<EOF` | ✅ PASS | ✅ PASS |
| `cat >file && chmod 755` (baseline) | ✅ PASS | ✅ PASS |
| `tempfile + install -m 755` (baseline) | ✅ PASS | ✅ PASS |
| `cat + chmod` on foreign-owned file | ✅ PASS (chmod fails as expected) | ✅ PASS (chmod fails as expected) |
| `install /dev/stdin` on foreign-owned file | ✅ PASS (overwrites & changes owner) | ✅ PASS (overwrites & changes owner) |
| `tempfile + install` on foreign-owned file | ✅ PASS (overwrites & changes owner) | ✅ PASS (overwrites & changes owner) |

### Platform Details

#### Linux (Ubuntu 24.04.3 LTS)
- **install command:** GNU coreutils 9.4
- **Location:** `/usr/bin/install`
- **Kernel:** Linux 6.11.0-1018-azure

#### macOS (Darwin 24.6.0)
- **install command:** BSD install
- **Location:** `/usr/bin/install`
- **OS:** macOS 15.7.2

## Key Findings

### ✅ Recommended Approaches (Portable)

Both of these patterns work reliably across Linux and macOS:

#### 1. **Heredoc with /dev/stdin** (Recommended for inline content)
```bash
install -m 755 /dev/stdin target <<'EOF'
#!/usr/bin/env bash
echo "script content"
EOF
```

**Pros:**
- Works on both Linux and macOS
- Single command (atomic)
- Properly handles ownership changes on foreign-owned files
- Clean syntax for embedding scripts

**Cons:**
- None identified

#### 2. **Temporary file + install** (Recommended for variable content)
```bash
tmp=$(mktemp)
printf '%s\n' "$SCRIPT_CONTENT" > "$tmp"
install -m 755 "$tmp" target
rm -f "$tmp"
```

**Pros:**
- Works on both Linux and macOS
- Properly handles ownership changes on foreign-owned files
- Good for content in variables
- Most traditional approach

**Cons:**
- Requires cleanup of temporary file
- Multiple commands (not atomic)

### 🔍 Alternative: /dev/fd/0

The pattern `install -m 755 /dev/fd/0 target <<EOF` also works on both platforms and is functionally equivalent to `/dev/stdin`.

### ❌ Non-Portable: Piped stdin

The pattern `echo "content" | install -m 755 /dev/stdin target` has **platform-dependent behavior**:
- **Linux (GNU coreutils):** ✅ Works correctly
- **macOS (BSD install):** ❌ Fails with exit code 71

**Do not use this pattern** if cross-platform compatibility is needed.

### 🚨 Broken Pattern: cat + chmod

The classic `cat >file && chmod 755 file` pattern has a **critical flaw** when the target file is owned by another user (e.g., root):

```bash
# If 'target' is owned by root but world-writable:
cat >target <<EOF  # ✅ Succeeds (file is writable)
#!/bin/bash
echo "new content"
EOF

chmod 755 target   # ❌ FAILS (you don't own the file)
```

This leaves the file with the new content but **without execute permissions**, breaking the script.

**Both `install` approaches (heredoc and tempfile)** solve this problem by atomically replacing the file, including ownership.

## Foreign-Owned File Behavior

When replacing a file owned by another user (e.g., a root-owned file in a user-writable directory):

| Method | Behavior | Result |
|--------|----------|---------|
| `cat >file && chmod` | ❌ chmod fails | File updated but not executable |
| `install /dev/stdin` | ✅ Replaces file | New owner (current user), mode 755 |
| `tempfile + install` | ✅ Replaces file | New owner (current user), mode 755 |

Both `install` methods properly handle ownership transfer, while `cat + chmod` breaks.

## Test Script

The test suite ([test-install-portability.sh](./test-install-portability.sh)) validates:
1. Basic functionality of each approach
2. Proper handling of foreign-owned files (requires sudo)
3. Platform-specific behaviors

Run locally:
```bash
./test-install-portability.sh
```

## Recommendations

1. **For inline script content:** Use `install -m 755 /dev/stdin target <<EOF`
2. **For variable content:** Use temporary file + `install -m 755 "$tmp" target`
3. **Avoid:** Piped stdin (`echo | install /dev/stdin`) for cross-platform code
4. **Never use:** `cat >file && chmod` when file ownership might change

## References

- [GNU coreutils install documentation](https://www.gnu.org/software/coreutils/manual/html_node/install-invocation.html)
- [FreeBSD install man page](https://man.freebsd.org/cgi/man.cgi?query=install&sektion=1) (similar to macOS BSD)
- Test workflow: [.github/workflows/test-install-portability.yml](.github/workflows/test-install-portability.yml)
