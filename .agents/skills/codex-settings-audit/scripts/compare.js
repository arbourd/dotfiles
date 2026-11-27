// Compares agents/codex/config.toml with ~/.codex/config.toml.
// Usage: bun .agents/skills/codex-settings-audit/scripts/compare.js (read-only).

const { execFileSync } = require('child_process');
const { existsSync } = require('fs');
const os = require('os');
const path = require('path');
const { isDeepStrictEqual } = require('util');

const REPO_PATH = path.join(__dirname, '../../../../agents/codex/config.toml');
const LIVE_PATH = path.join(os.homedir(), '.codex/config.toml');

// Ignore machine-specific keys and keys that Codex writes itself.
const LOCAL_KEYS = new Set([
  'model', 'model_provider', 'model_reasoning_effort', 'model_providers', 'projects', 'notice',
  'cli_auth_credentials_store', 'mcp_oauth_credentials_store', 'hooks.state',
  'tui.model_availability_nux', 'tui.screen_reader_detection_done',
]);

const fail = (message) => {
  console.error(`compare.js: ${message}`);
  process.exit(1);
};

// Match dot's yq TOML parsing. Missing or empty files count as {}.
const parseToml = (file) => {
  if (!existsSync(file)) return {};
  try {
    return JSON.parse(execFileSync('yq', ['-p', 'toml', '-o', 'json', '.', file], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })) ?? {};
  } catch (error) {
    fail(`${file}: ${error.stderr?.toString().trim() || error.message}`);
  }
};

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

const preview = (value) => {
  const text = JSON.stringify(value);
  return text?.length > 70 ? `${text.slice(0, 70)}…` : text;
};

// Yields [dotted key, repo value, live value] for values the merge has not applied.
// Tables merge key by key. Arrays and scalars must match exactly.
function* unapplied(ours, live, parents = []) {
  for (const [key, value] of Object.entries(ours)) {
    const keyPath = [...parents, key];
    const liveValue = live[key];
    if (isObject(value) && isObject(liveValue)) yield* unapplied(value, liveValue, keyPath);
    else if (!isDeepStrictEqual(value, liveValue)) yield [keyPath.join('.'), value, liveValue];
  }
}

const ours = parseToml(REPO_PATH);
const live = parseToml(LIVE_PATH);

console.log('# Unapplied: in config.toml, not yet in ~/.codex/config.toml');
for (const [key, value, liveValue] of unapplied(ours, live)) {
  console.log(`${key} ours=${preview(value)} live=${preview(liveValue)}`);
}

// Yields [dotted key, value] for live values that the repo lacks, skipping machine-local keys.
// A key set in both files is not drift, because Unapplied shows any difference.
function* drift(live, ours, parents = []) {
  for (const [key, value] of Object.entries(live)) {
    const keyPath = [...parents, key];
    const dotted = keyPath.join('.');
    if (LOCAL_KEYS.has(dotted)) continue;
    const has = Object.hasOwn(ours, key);
    if (isObject(value) && (!has || isObject(ours[key]))) yield* drift(value, has ? ours[key] : {}, keyPath);
    else if (!has) yield [dotted, value];
  }
}

console.log('\n# Live drift: set in ~/.codex/config.toml, not in config.toml');
for (const [key, value] of drift(live, ours)) console.log(`${key} live=${preview(value)}`);
