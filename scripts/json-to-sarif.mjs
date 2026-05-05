#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

const [inputPath, outputPath, toolVersion = 'unknown'] = process.argv.slice(2);

if (!inputPath || !outputPath) {
  console.error('Usage: json-to-sarif.mjs <cognium-json> <output-sarif> [tool-version]');
  process.exit(2);
}

function readJson(file) {
  if (!fs.existsSync(file) || fs.statSync(file).size === 0) {
    return {};
  }
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function collectFindings(data) {
  if (Array.isArray(data)) return data;
  for (const key of ['findings', 'results', 'vulnerabilities', 'issues']) {
    if (Array.isArray(data?.[key])) return data[key];
  }
  if (Array.isArray(data?.scan?.findings)) return data.scan.findings;
  if (Array.isArray(data?.summary?.findings)) return data.summary.findings;
  return [];
}

function firstDefined(...values) {
  return values.find((value) => value !== undefined && value !== null && value !== '');
}

function normalizeLevel(severity) {
  switch (String(severity || '').toLowerCase()) {
    case 'critical':
    case 'high':
    case 'error':
      return 'error';
    case 'medium':
    case 'warning':
      return 'warning';
    case 'low':
    case 'info':
    case 'note':
      return 'note';
    default:
      return 'warning';
  }
}

function normalizeSecuritySeverity(severity) {
  switch (String(severity || '').toLowerCase()) {
    case 'critical':
      return '9.0';
    case 'high':
      return '7.0';
    case 'medium':
      return '5.0';
    case 'low':
      return '3.0';
    default:
      return '5.0';
  }
}

function normalizeRuleId(finding) {
  return String(firstDefined(
    finding.ruleId,
    finding.rule_id,
    finding.rule,
    finding.cwe,
    finding.checkId,
    finding.type,
    finding.category,
    finding.id,
    'cognium-ai-finding'
  ));
}

function normalizeMessage(finding, ruleId) {
  return String(firstDefined(
    finding.message,
    finding.explanation,
    finding.description,
    finding.title,
    finding.reason,
    finding.type,
    ruleId
  ));
}

function normalizePath(finding) {
  return String(firstDefined(
    finding.file,
    finding.filePath,
    finding.path,
    finding.location?.file,
    finding.location?.path,
    finding.sink?.file,
    finding.source?.file,
    'unknown'
  ));
}

function normalizeLine(finding) {
  const line = Number(firstDefined(
    finding.line,
    finding.startLine,
    finding.location?.line,
    finding.location?.startLine,
    finding.sink?.line,
    finding.source?.line,
    1
  ));
  return Number.isFinite(line) && line > 0 ? line : 1;
}

function buildRules(findings) {
  const rules = new Map();
  for (const finding of findings) {
    const ruleId = normalizeRuleId(finding);
    if (rules.has(ruleId)) continue;
    const severity = firstDefined(finding.severity, finding.level, 'medium');
    rules.set(ruleId, {
      id: ruleId,
      name: String(firstDefined(finding.name, finding.type, ruleId)),
      shortDescription: { text: String(firstDefined(finding.title, finding.message, ruleId)) },
      fullDescription: { text: String(firstDefined(finding.description, finding.explanation, finding.message, ruleId)) },
      help: { text: String(firstDefined(finding.remediation, finding.fix, 'Review the finding and validate exploitability before remediation.')) },
      properties: {
        tags: ['security', 'cognium-ai'],
        security_severity: normalizeSecuritySeverity(severity),
      },
    });
  }
  return [...rules.values()];
}

function buildCodeFlows(finding) {
  const pathItems = asArray(finding.path || finding.trace || finding.flows);
  if (pathItems.length === 0) return undefined;

  const locations = pathItems.map((item) => ({
    location: {
      physicalLocation: {
        artifactLocation: { uri: String(firstDefined(item.file, item.path, normalizePath(finding))) },
        region: { startLine: Number(firstDefined(item.line, item.startLine, 1)) || 1 },
      },
    },
  }));

  return [{ threadFlows: [{ locations }] }];
}

function buildResults(findings) {
  return findings.map((finding) => {
    const ruleId = normalizeRuleId(finding);
    const result = {
      ruleId,
      level: normalizeLevel(firstDefined(finding.severity, finding.level, 'medium')),
      message: { text: normalizeMessage(finding, ruleId) },
      locations: [
        {
          physicalLocation: {
            artifactLocation: { uri: normalizePath(finding) },
            region: { startLine: normalizeLine(finding) },
          },
        },
      ],
    };

    const codeFlows = buildCodeFlows(finding);
    if (codeFlows) result.codeFlows = codeFlows;
    return result;
  });
}

const data = readJson(inputPath);
const findings = collectFindings(data);
const sarif = {
  $schema: 'https://json.schemastore.org/sarif-2.1.0.json',
  version: '2.1.0',
  runs: [
    {
      tool: {
        driver: {
          name: 'cognium-ai',
          version: toolVersion.trim() || 'unknown',
          informationUri: 'https://github.com/cogniumhq/cognium-ai-action',
          rules: buildRules(findings),
        },
      },
      results: buildResults(findings),
    },
  ],
};

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(sarif, null, 2) + '\n');
