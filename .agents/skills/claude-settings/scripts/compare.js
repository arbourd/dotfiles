// Compares agents/claude/settings.jsonc with ~/.claude/settings.json.
// Usage: node .agents/skills/claude-settings/scripts/compare.js   (read-only)

const { execFileSync } = require('child_process');
const os = require('os');
const path = require('path');
const { isDeepStrictEqual } = require('util');

const REPO_PATH = path.join(__dirname, '../../../../agents/claude/settings.jsonc');
const LIVE_PATH = path.join(os.homedir(), '.claude/settings.json');

// Machine-specific or installed by other tools; never belongs in the repo.
const LOCAL_KEYS = new Set(['hooks', 'apiKeyHelper']);

// sqlite's json() reads JSONC, the same way _merge_claude_settings in dot does.
// CAST stops json() reading the file as JSONB. A missing or blank file counts as {}.
const parseJsonc = (file) => {
  const sqlPath = file.replaceAll("'", "''"); // double ' inside the SQL string literal
  const query = `SELECT json(coalesce(nullif(trim(CAST(readfile('${sqlPath}') AS TEXT), ' '||char(9,10,13)), ''), '{}'))`;
  return JSON.parse(execFileSync('sqlite3', [':memory:', query], { encoding: 'utf8' }));
};

const preview = (value) => JSON.stringify(value)?.slice(0, 70);

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

// Whether `ours` is in `live` after the json_patch merge: extra live object keys are fine, null means absent.
function isApplied(ours, live) {
  if (ours === null) return live === undefined;
  if (isObject(ours) && isObject(live)) {
    return Object.entries(ours).every(([key, value]) => isApplied(value, live[key]));
  }
  return isDeepStrictEqual(ours, live);
}

const ours = parseJsonc(REPO_PATH);
const live = parseJsonc(LIVE_PATH);

console.log('# Unapplied: in settings.jsonc, not yet in ~/.claude/settings.json');
for (const [key, value] of Object.entries(ours)) {
  if (!isApplied(value, live[key])) console.log(`${key} ours=${preview(value)} live=${preview(live[key])}`);
}

// Yields [dotted key, value] for live entries settings.jsonc lacks, descending into objects both set.
function* drift(live, ours, parents = []) {
  for (const [key, value] of Object.entries(live)) {
    const keyPath = [...parents, key];
    if (!Object.hasOwn(ours, key)) yield [keyPath.join('.'), value];
    else if (isObject(value) && isObject(ours[key])) yield* drift(value, ours[key], keyPath);
  }
}

console.log('\n# Live drift: set in ~/.claude/settings.json, not in settings.jsonc');
for (const [key, value] of drift(live, ours)) {
  if (!LOCAL_KEYS.has(key)) console.log(`${key} live=${preview(value)}`);
}
