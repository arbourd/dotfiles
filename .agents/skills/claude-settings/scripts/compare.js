// Compares agents/claude/settings.jsonc with ~/.claude/settings.json, using the merge `dot merge claude` runs.
// Usage: node .agents/skills/claude-settings/scripts/compare.js   (read-only)

// Machine-specific keys that never belong in the repo; Live drift hides them. Top-level only.
const LOCAL_KEYS = new Set(['apiKeyHelper', 'hooks']);

const { execFileSync } = require('child_process');
const os = require('os');
const path = require('path');
const { isDeepStrictEqual } = require('util');

const REPO_PATH = path.join(__dirname, '../../../../agents/claude/settings.jsonc');
const LIVE_PATH = path.join(os.homedir(), '.claude/settings.json');

const fail = (message) => {
  console.error(`compare.js: ${message}`);
  process.exit(1);
};

// Same SQL as _merge_claude_settings in dot: json() reads JSONC, CAST avoids JSONB.
// A missing or blank live file is {}; a missing repo file aborts, as in dot.
const quote = (file) => file.replaceAll("'", "''"); // escape ' for SQL
const liveSql = `json(coalesce(nullif(trim(CAST(readfile('${quote(LIVE_PATH)}') AS TEXT), ' '||char(9,10,13)), ''), '{}'))`;
const repoSql = `json(CAST(readfile('${quote(REPO_PATH)}') AS TEXT))`;

// Runs a SELECT through sqlite3 and parses the JSON it prints. Empty output is NULL, a failed merge in dot.
const query = (select, what) => {
  let out;
  try {
    out = execFileSync('sqlite3', [':memory:', `SELECT ${select}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  } catch (error) {
    fail(`${what}: ${error.stderr?.toString().trim() || error.message}`);
  }
  if (!out) fail(`${what} is missing, so dot merge would abort`);
  return JSON.parse(out); // known limit: numbers JSON.parse can't tell apart (huge ints, 1 vs 1.0, 0 vs -0) look unchanged
};

const preview = (value) => {
  const text = JSON.stringify(value);
  return text?.length > 70 ? `${text.slice(0, 70)}…` : text;
};

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

const ours = query(repoSql, 'settings.jsonc');
// json_patch returns a non-object patch as the result, so it would replace the whole live file.
if (!isObject(ours)) fail('settings.jsonc must be a JSON object, or dot merge would replace the whole live file with it');

const liveRaw = query(liveSql, '~/.claude/settings.json');
// json_patch treats a non-object target as {}, so that live file is lost entirely.
const liveIsObject = isObject(liveRaw);
const live = liveIsObject ? liveRaw : {};
// What `dot merge claude` writes: json_patch (RFC 7396), repo wins.
const merged = query(`json_patch(${liveSql}, ${repoSql})`, 'merge result');

// Own properties only, so inherited names like constructor read as missing.
const own = (object, key) => (Object.hasOwn(object, key) ? object[key] : undefined);

// Yields [dotted key, before, after] for each differing leaf.
function* changes(before, after, parents = []) {
  for (const key of new Set([...Object.keys(before), ...Object.keys(after)])) {
    const keyPath = [...parents, key];
    const [was, now] = [own(before, key), own(after, key)];
    if (isObject(was) && isObject(now)) yield* changes(was, now, keyPath);
    else if (!isDeepStrictEqual(was, now)) yield [keyPath.join('.'), was, now];
  }
}

// Yields [dotted key, value] for live entries the repo file lacks.
function* drift(live, ours, parents = []) {
  for (const [key, value] of Object.entries(live)) {
    const keyPath = [...parents, key];
    if (!Object.hasOwn(ours, key)) yield [keyPath.join('.'), value];
    else if (isObject(value) && isObject(ours[key])) yield* drift(value, ours[key], keyPath);
  }
}

// Whether replacing `before` with `after` loses live data. Missing, null and empty values hold nothing to lose.
const isEmpty = (value) => (Array.isArray(value) ? value.length === 0 : isObject(value) && Object.keys(value).length === 0);
const loses = (before, after) => {
  if (before === undefined || before === null || isEmpty(before)) return false;
  if (after === undefined) return true;
  if (Array.isArray(before) && Array.isArray(after)) return before.some((item) => !after.some((kept) => isDeepStrictEqual(kept, item)));
  return isObject(before) || Array.isArray(before);
};

const all = [...changes(live, merged)];

// REPO_PATH is this script's checkout, which may not be the one `dot` merges from.
console.log(`# Comparing ${REPO_PATH} with ${LIVE_PATH.replace(os.homedir(), '~')}\n`);

console.log('# Unapplied: what `dot merge claude` would change in ~/.claude/settings.json');
for (const [key, before, after] of all) console.log(`${key} live=${preview(before)} merged=${preview(after)}`);

console.log('\n# Live drift: set in ~/.claude/settings.json, not in settings.jsonc');
for (const [key, value] of drift(live, ours)) {
  if (!LOCAL_KEYS.has(key)) console.log(`${key} live=${preview(value)}`);
}

console.log('\n# Merge risks: live data the merge would delete or overwrite');
if (!liveIsObject && liveRaw !== null) console.log(`(whole file) live=${preview(liveRaw)} is not a JSON object; the merge replaces it`);
for (const [key, before, after] of all) {
  if (loses(before, after)) console.log(`${key} live=${preview(before)} merged=${preview(after)}`);
}
