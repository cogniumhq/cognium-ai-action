#!/usr/bin/env bash
set -euo pipefail

target="${INPUT_PATH:-.}"
package_version="${INPUT_PACKAGE_VERSION:-latest}"
mode="${INPUT_MODE:-static}"
language="${INPUT_LANGUAGE:-auto}"
file_timeout="${INPUT_FILE_TIMEOUT:-30}"

out_dir="${RUNNER_TEMP:-/tmp}/cognium-ai"
json_file="$out_dir/results.json"
sarif_file="$out_dir/results.sarif"
version_file="$out_dir/version.txt"

mkdir -p "$out_dir"

echo "Installing cognium-ai@$package_version"
npm install -g "cognium-ai@$package_version"

cognium-ai --version > "$version_file" 2>/dev/null || true

scan_args=(scan "$target" -f json -o "$json_file" --file-timeout "$file_timeout" --quiet)

case "$mode" in
  static)
    scan_args+=(--no-llm)
    ;;
  llm)
    scan_args+=(--llm)
    ;;
  enrich)
    scan_args+=(--llm-enrich)
    ;;
  verify)
    scan_args+=(--llm-verify)
    ;;
  *)
    echo "Unsupported cognium-ai mode: $mode" >&2
    echo "Use one of: static, llm, enrich, verify" >&2
    exit 2
    ;;
esac

if [[ -n "$language" && "$language" != "auto" && "$language" != "all" ]]; then
  scan_args+=(--language "$language")
fi

if [[ -n "${INPUT_LLM_BASE_URL:-}" ]]; then
  scan_args+=(--llm-base-url "$INPUT_LLM_BASE_URL")
fi

if [[ -n "${INPUT_LLM_API_KEY:-}" ]]; then
  scan_args+=(--llm-api-key "$INPUT_LLM_API_KEY")
fi

if [[ -n "${INPUT_LLM_MODEL:-}" ]]; then
  scan_args+=(--llm-model "$INPUT_LLM_MODEL")
fi

if [[ -n "${INPUT_MAX_FILES:-}" ]]; then
  scan_args+=(--max-files "$INPUT_MAX_FILES")
fi

if [[ -n "${INPUT_CATEGORIES:-}" ]]; then
  IFS=',' read -r -a categories <<< "$INPUT_CATEGORIES"
  for category in "${categories[@]}"; do
    trimmed="$(echo "$category" | xargs)"
    if [[ -n "$trimmed" ]]; then
      scan_args+=(--category "$trimmed")
    fi
  done
fi

if [[ -n "${INPUT_EXTRA_ARGS:-}" ]]; then
  read -r -a extra_args <<< "$INPUT_EXTRA_ARGS"
  scan_args+=("${extra_args[@]}")
fi

echo "Running cognium-ai ${scan_args[*]}"
cognium-ai "${scan_args[@]}"

node "$GITHUB_ACTION_PATH/scripts/json-to-sarif.mjs" "$json_file" "$sarif_file" "$(cat "$version_file" 2>/dev/null || true)"

findings_total="$(node -e "const fs=require('fs'); const s=fs.readFileSync(process.argv[1],'utf8'); const j=JSON.parse(s); const r=j.runs?.[0]?.results || []; console.log(r.length)" "$sarif_file")"

{
  echo "json-file=$json_file"
  echo "sarif-file=$sarif_file"
  echo "findings-total=$findings_total"
} >> "$GITHUB_OUTPUT"

echo "Generated $sarif_file with $findings_total finding(s)."
