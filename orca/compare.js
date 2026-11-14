// Compares orca/settings.jsonc with Orca's defaults and its live profile db.
// Usage: node orca/compare.js   (runs orca/defaults.js; read-only, fine while Orca runs)

const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');

const run = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 1 << 26 });
const db = path.join(os.homedir(), 'Library/Application Support/orca/profiles/local-default/profile-state.db');
const defaults = JSON.parse(run('node', [path.join(__dirname, 'defaults.js')]));
const payload = run('sqlite3', ['-readonly', db, "SELECT payload FROM profile_state_documents WHERE domain='settings'"]).trim();
if (!payload) {
  console.error(`no settings row in ${db}`);
  process.exit(1);
}
const live = JSON.parse(payload);
// JSONC: only whole-line // comments are used in settings.jsonc.
const ours = JSON.parse(fs.readFileSync(path.join(__dirname, 'settings.jsonc'), 'utf8').replace(/^\s*\/\/.*$/gm, ''));

// Orca-managed state, not preferences: telemetry, consents, seeds, migrations, dismissed prompts.
const internal = /^(telemetry|pluginConsents|activeClaudeManagedAccountIds)|Seed$|Migrated|Dismissed|SyncOffer/;

const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);
// Key order differs between our file and the db, so compare with sorted keys.
const canon = (v) => (isObj(v) ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, canon(v[k])])) : Array.isArray(v) ? v.map(canon) : v);
const eq = (a, b) => JSON.stringify(canon(a)) === JSON.stringify(canon(b));
const empty = (v) => v == null || v === '' || (Array.isArray(v) ? !v.length : isObj(v) && !Object.keys(v).length);
// [dotted key, value] leaves of o; descends into a value only when descend(value, key) says so.
const walk = (o, descend, p = '') => Object.entries(o).flatMap(([k, v]) => (descend(v, p + k) ? walk(v, descend, `${p}${k}.`) : [[p + k, v]]));
const get = (o, k) => k.split('.').reduce((a, x) => (a == null ? undefined : a[x]), o);
const show = (v) => JSON.stringify(v)?.slice(0, 70);

const flat = (o) => walk(o, (v) => isObj(v) && !empty(v));
// Ours descends only where Orca's default is also an object.
const leaves = (o) => walk(o, (v, k) => isObj(v) && isObj(get(defaults, k)));

console.log('# Our keys: check each // Default: comment against the default shown');
for (const [k, v] of leaves(ours)) {
  const d = get(defaults, k), l = get(live, k);
  const flags = [
    v !== null && eq(v, d) && 'equals default: drop',
    v !== null && d === undefined && !k.includes('.') && 'not in defaults: unset-by-default key, or removed/renamed?',
    v !== null && !eq(v, l) && 'db differs: unapplied',
    v === null && !empty(l) && 'null still has a value in the db: unapplied, or Orca repopulated it',
  ].filter(Boolean);
  console.log(`${k} ours=${show(v)} default=${show(d)}${flags.length ? ` -> ${flags.join('; ')}` : ''}`);
}

console.log('\n# Live drift: set in the db, not in settings.jsonc');
for (const [k, l] of flat(live)) {
  const d = get(defaults, k);
  if (internal.test(k) || get(ours, k) !== undefined || eq(l, d) || (d === undefined && empty(l))) continue;
  console.log(`${k} live=${show(l)} default=${show(d)}`);
}

console.log('\n# New default keys absent from the db');
for (const [k, d] of flat(defaults)) if (get(live, k) === undefined) console.log(`${k} default=${show(d)}`);
