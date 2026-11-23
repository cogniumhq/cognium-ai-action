#!/usr/bin/env bash
# Runs scripts/run.sh against stub npm and cognium-ai binaries and checks that
# secret inputs never reach the log or the cognium-ai command line.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"

cat > "$work/bin/npm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$work/bin/cognium-ai" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  echo "0.0.0-stub"
  exit 0
fi
printf '%s\n' "$@" >> "$STUB_ARGV_LOG"
printf '%s\n' "${LLM_API_KEY:-}" >> "$STUB_ENV_LOG"
# cognium-ai 4.28.0 has no --llm-enrich and rejects unknown options.
for arg in "$@"; do
  if [[ "$arg" == "--llm-enrich" ]]; then
    echo "error: unknown option '$arg'" >&2
    exit 1
  fi
done
out=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    out="$2"
    shift
  fi
  shift
done
echo '{"version":"2.1.0","runs":[{"results":[]}]}' > "$out"
EOF

chmod +x "$work/bin/npm" "$work/bin/cognium-ai"

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

# run_case <name> <secret...> -- <env assignments...>
run_case() {
  local name="$1"
  shift
  local -a secrets=()
  while [[ "$1" != "--" ]]; do
    secrets+=("$1")
    shift
  done
  shift

  local before="$failures"
  local case_dir="$work/$name"
  mkdir -p "$case_dir"
  : > "$case_dir/argv"
  : > "$case_dir/env"
  : > "$case_dir/github_output"

  if ! env -i PATH="$work/bin:$PATH" HOME="$HOME" \
    RUNNER_TEMP="$case_dir" \
    GITHUB_OUTPUT="$case_dir/github_output" \
    STUB_ARGV_LOG="$case_dir/argv" \
    STUB_ENV_LOG="$case_dir/env" \
    "$@" \
    bash "$script_dir/run.sh" > "$case_dir/log" 2>&1; then
    fail "$name: run.sh exited non-zero"
    cat "$case_dir/log" >&2
    return
  fi

  # ::add-mask:: lines are consumed by the runner and never shown in the log.
  grep -v '^::add-mask::' "$case_dir/log" > "$case_dir/visible" || true

  local secret
  for secret in "${secrets[@]}"; do
    if grep -qF -- "$secret" "$case_dir/visible"; then
      fail "$name: secret appears in the log"
    fi
    if ! grep -qxF -- "::add-mask::$secret" "$case_dir/log"; then
      fail "$name: secret was not registered with ::add-mask::"
    fi
  done

  if [[ "$failures" -eq "$before" ]]; then
    echo "ok: $name"
  fi
}

input_key="test-input-key-0b7f3c"
run_case input-key "$input_key" -- \
  INPUT_MODE=llm \
  INPUT_JSON_OUTPUT=true \
  INPUT_LLM_API_KEY="$input_key" \
  INPUT_LLM_MODEL=test-model

if grep -qF -- "$input_key" "$work/input-key/argv"; then
  fail "input-key: key was passed on the cognium-ai command line"
fi
if [[ "$(sort -u "$work/input-key/env")" != "$input_key" ]]; then
  fail "input-key: LLM_API_KEY was not passed to cognium-ai"
fi

extra_key="test-extra-key-91d2aa"
extra_eq_key="test-extra-eq-key-5c4e10"
run_case extra-args "$extra_key" "$extra_eq_key" -- \
  INPUT_MODE=llm \
  INPUT_EXTRA_ARGS="--llm-api-key $extra_key --llm-api-key=$extra_eq_key"

url_pass="test-url-pass-77a1e9"
run_case base-url "user:$url_pass" -- \
  INPUT_MODE=llm \
  INPUT_LLM_BASE_URL="https://user:$url_pass@llm.example.com/v1"

if grep -qF -- "$url_pass" "$work/base-url/visible"; then
  fail "base-url: URL password appears in the log"
fi

enrich_key="test-enrich-key-e4a8d1"
run_case enrich "$enrich_key" -- \
  INPUT_MODE=enrich \
  INPUT_LLM_API_KEY="$enrich_key"

if ! grep -qxF -- "--llm" "$work/enrich/argv" ||
  ! grep -qxF -- "--no-llm-verify" "$work/enrich/argv"; then
  fail "enrich: expected --llm --no-llm-verify on the cognium-ai command line"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi

echo "All self-tests passed."
