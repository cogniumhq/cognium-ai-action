# Cognium AI Security Scan

Run `cognium-ai` in GitHub Actions and publish SARIF results to GitHub code scanning.

This action is intended for the GitHub Actions Marketplace under the Security category. It installs the `cognium-ai` npm package, scans the repository, converts JSON output to SARIF, and optionally uploads the SARIF file through `github/codeql-action/upload-sarif`.

## Usage

```yaml
name: Cognium AI Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

permissions:
  contents: read
  security-events: write

jobs:
  cognium-ai:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cogniumhq/cognium-ai-action@v1
        with:
          mode: static
          path: .
          upload-sarif: "true"
```

## LLM-Enriched Scan

GitHub Models requires `models: read`.

```yaml
permissions:
  contents: read
  security-events: write
  models: read

jobs:
  cognium-ai:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cogniumhq/cognium-ai-action@v1
        with:
          mode: llm
          llm-base-url: https://models.github.ai/inference
          llm-api-key: ${{ github.token }}
          llm-model: openai/gpt-4o-mini
```

## Inputs

| Input | Default | Description |
| --- | --- | --- |
| `path` | `.` | Path to scan, relative to the repository root. |
| `package-version` | `latest` | npm version of `cognium-ai` to install. |
| `mode` | `static` | `static`, `llm`, `enrich`, or `verify`. |
| `language` | `auto` | Optional language filter such as `java`, `javascript`, `typescript`, `python`, `rust`, or `bash`. |
| `upload-sarif` | `true` | Upload SARIF results to GitHub code scanning. |
| `fail-on-findings` | `false` | Fail the job when one or more findings are reported. |
| `llm-base-url` | empty | OpenAI-compatible LLM base URL for LLM mode. |
| `llm-api-key` | empty | LLM API key. Prefer GitHub secrets or `github.token`. |
| `llm-model` | empty | LLM model name for LLM mode. |
| `file-timeout` | `30` | Per-file scan timeout in seconds. |
| `max-files` | empty | Optional maximum number of files to scan. |
| `categories` | empty | Optional comma-separated category filters. |
| `extra-args` | empty | Additional trusted `cognium-ai scan` arguments. |

## Outputs

| Output | Description |
| --- | --- |
| `sarif-file` | Path to the generated SARIF file. |
| `json-file` | Path to the raw `cognium-ai` JSON result file. |
| `findings-total` | Total findings parsed into SARIF. |

## Marketplace Publishing

1. Keep this repository public.
2. Keep a single root `action.yml` metadata file.
3. Do not add `.github/workflows` to this repository before Marketplace publication.
4. Draft a release, select **Publish this Action to the GitHub Marketplace**, and choose **Security** as the primary category.
5. Publish the first release as `v1.0.0`, then move or create a `v1` major-version tag for user workflows.

## License

MIT
