// Compares agents/claude/settings.jsonc with ~/.claude/settings.json and config.jsonc with ~/.claude.json,
// using the merge `dot merge claude` runs.
// Usage: bun .agents/skills/claude-settings-audit/scripts/compare.js   (read-only)

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { isDeepStrictEqual } = require('util');

const REPO_DIR = path.join(__dirname, '../../../../agents/claude');

const fail = (message) => {
  console.error(`compare.js: ${message}`);
  process.exit(1);
};

// Live drift hides the top-level keys listed per repo file in denylist.json: machine-specific keys for settings.jsonc,
// app state Claude Code rewrites for config.jsonc. A state key added later shows as drift; add it there.
let DENYLIST;
try {
  DENYLIST = JSON.parse(fs.readFileSync(path.join(__dirname, 'denylist.json'), 'utf8'));
} catch (error) {
  fail(`denylist.json: ${error.message}`);
}

// ~/.claude.json grows with history; 10 MiB is far beyond any real file but stops a runaway read.
const MAX_OUTPUT = 10 * 1024 * 1024;

const quote = (file) => file.replaceAll("'", "''"); // escape ' for SQL

// Runs a SELECT through sqlite3 and parses the JSON it prints. Empty output is NULL, a failed merge in dot.
const query = (select, what) => {
  let out;
  try {
    out = execFileSync('sqlite3', [':memory:', `SELECT ${select}`], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], maxBuffer: MAX_OUTPUT }).trim();
  } catch (error) {
    fail(`${what}: ${error.stderr?.toString().trim() || error.message}`);
  }
  if (!out) fail(`${what} is missing, so dot merge would abort`);
  return JSON.parse(out); // known limit: numbers JSON.parse can't tell apart (huge ints, 1 vs 1.0, 0 vs -0) look unchanged
};

const isObject = (value) => value !== null && typeof value === 'object' && !Array.isArray(value);

// Hide secret strings, by key name only, before values reach the agent transcript.
// Secrets inside args, commands, or URLs still print.
const SECRET_WORD = /(token|secret|password|passwd|key|credential|cookie|auth)s?$|^(authorization|bearer|pat)$/i;
const SECRET_TABLE = /(^|\.)(env|headers|http_headers|shell_environment_policy\.set)\./;
const lastWord = (key) => key.split(/[-_]|(?<=[a-z])(?=[A-Z])|(?<=[A-Z])(?=[A-Z][a-z])/).at(-1);
const isSecret = (key) => key.split('.').some((part) => SECRET_WORD.test(lastWord(part))) || SECRET_TABLE.test(key);

const redact = (key, value) => {
  if (Array.isArray(value)) return value.map((item, i) => redact(`${key}.${i}`, item));
  if (isObject(value)) return Object.fromEntries(Object.entries(value).map(([child, item]) => [child, redact(`${key}.${child}`, item)]));
  return typeof value === 'string' && isSecret(key) ? '<redacted>' : value;
};

const preview = (key, value) => {
  const text = JSON.stringify(redact(key, value));
  return text?.length > 70 ? `${text.slice(0, 70)}…` : text;
};

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

// Returns the report for one repo file and its live file, as a string. Live drift skips the repoFile's denylist keys.
function compare({ repoFile, livePath }) {
  const out = [];
  // Each line, or "(none)" so an empty section reads as checked, not cut off.
  const addAll = (lines) => out.push(...(lines.length ? lines : ['(none)']));
  if (!Array.isArray(DENYLIST[repoFile])) fail(`denylist.json must list ${repoFile} as an array of keys`);
  const denied = new Set(DENYLIST[repoFile]);
  const repoPath = path.join(REPO_DIR, repoFile);
  const liveName = livePath.replace(os.homedir(), '~');

  // Same SQL as _merge_claude_settings in dot: json() reads JSONC, CAST avoids JSONB.
  // A missing or blank live file is {}; a missing repo file aborts, as in dot.
  const liveSql = `json(coalesce(nullif(trim(CAST(readfile('${quote(livePath)}') AS TEXT), ' '||char(9,10,13)), ''), '{}'))`;
  const repoSql = `json(CAST(readfile('${quote(repoPath)}') AS TEXT))`;

  const ours = query(repoSql, repoFile);
  // json_patch returns a non-object patch as the result, so it would replace the whole live file.
  if (!isObject(ours)) fail(`${repoFile} must be a JSON object, or dot merge would replace the whole live file with it`);

  const liveRaw = query(liveSql, liveName);
  // json_patch treats a non-object target as {}, so that live file is lost entirely.
  const liveIsObject = isObject(liveRaw);
  const live = liveIsObject ? liveRaw : {};
  // What `dot merge claude` writes: json_patch (RFC 7396), repo wins.
  const merged = query(`json_patch(${liveSql}, ${repoSql})`, `${repoFile} merge result`);
  const all = [...changes(live, merged)];

  // repoPath is this script's checkout, which may not be the one `dot` merges from.
  out.push(`# ${repoFile} → ${liveName}`, `(${repoPath})`, '');

  out.push('## Unapplied');
  addAll(all.map(([key, before, after]) => `${key} live=${preview(key, before)} merged=${preview(key, after)}`));

  out.push('', '## Live drift');
  addAll([...drift(live, ours)].filter(([key]) => !denied.has(key)).map(([key, value]) => `${key} live=${preview(key, value)}`));

  out.push('', '## Merge risks');
  const risks = all.filter(([, before, after]) => loses(before, after)).map(([key, before, after]) => `${key} live=${preview(key, before)} merged=${preview(key, after)}`);
  if (!liveIsObject && liveRaw !== null) risks.unshift(`(whole file) live=${preview('', liveRaw)} is not a JSON object; the merge replaces it`);
  addAll(risks);
  return out.join('\n');
}

// Build both reports before printing, so a bad file aborts with no partial output, as in dot.
const reports = [
  compare({ repoFile: 'settings.jsonc', livePath: path.join(os.homedir(), '.claude/settings.json') }),
  compare({ repoFile: 'config.jsonc', livePath: path.join(os.homedir(), '.claude.json') }),
];
console.log(reports.join('\n\n'));
