// Compares orca/settings.jsonc with Orca's defaults and its live profile db.
// Usage: node orca/compare.js   (runs orca/defaults.js; read-only, fine while Orca runs)

const { execFileSync } = require('child_process');
const os = require('os');
const path = require('path');
const { isDeepStrictEqual } = require('util');

const DB_PATH = path.join(os.homedir(), 'Library/Application Support/orca/profiles/local-default/profile-state.db');

// Orca-managed state, not preferences.
const INTERNAL_KEY = /^(telemetry|pluginConsents|activeClaudeManagedAccountIds)|Seed$|Migrated|Dismissed|SyncOffer/;

const run = (cmd, args) => execFileSync(cmd, args, { encoding: 'utf8', maxBuffer: 1 << 26 });

function loadDefaults() {
  return JSON.parse(run(process.execPath, [path.join(__dirname, 'defaults.js')]));
}

function loadLive() {
  const query = "SELECT payload FROM profile_state_documents WHERE domain='settings'";
  const payload = run('sqlite3', ['-readonly', DB_PATH, query]).trim();
  if (!payload) {
    console.error(`no settings row in ${DB_PATH}`);
    process.exit(1);
  }
  return JSON.parse(payload);
}

function loadOurs() {
  // sqlite's json() parses the JSONC the same way `dot link` does.
  const file = path.join(__dirname, 'settings.jsonc');
  return JSON.parse(run('sqlite3', [':memory:', `SELECT json(readfile('${file}'))`]));
}

const isObject = (value) => value && typeof value === 'object' && !Array.isArray(value);

const isEmpty = (value) => {
  if (value == null || value === '') return true;
  if (Array.isArray(value)) return value.length === 0;
  return isObject(value) && Object.keys(value).length === 0;
};

const getPath = (obj, keyPath) => keyPath.reduce((node, key) => node?.[key], obj);

const preview = (value) => JSON.stringify(value)?.slice(0, 70);

// Whether `ours` is in `live`, like json_patch: extra live keys are fine, null means absent.
function isApplied(ours, live) {
  if (ours === null) return isEmpty(live);
  if (isObject(ours) && isObject(live)) {
    return Object.entries(ours).every(([key, value]) => isApplied(value, live[key]));
  }
  return isDeepStrictEqual(ours, live);
}

// Yields [keyPath, value] for each leaf; descends only where shouldDescend(value, keyPath).
function* leaves(obj, shouldDescend, parents = []) {
  for (const [key, value] of Object.entries(obj)) {
    const keyPath = [...parents, key];
    if (shouldDescend(value, keyPath)) yield* leaves(value, shouldDescend, keyPath);
    else yield [keyPath, value];
  }
}

const live = loadLive();
const ours = loadOurs();
const defaults = loadDefaults(); // slowest, so last

const settingLeaves = (obj) => leaves(obj, (value) => isObject(value) && !isEmpty(value));

// Descend only where Orca's default is also an object.
const ourLeaves = (obj) => leaves(obj, (value, keyPath) => isObject(value) && isObject(getPath(defaults, keyPath)));

console.log('# Our keys: check each // Default: comment against the default shown');
for (const [keyPath, value] of ourLeaves(ours)) {
  const key = keyPath.join('.');
  const defaultValue = getPath(defaults, keyPath);
  const liveValue = getPath(live, keyPath);
  const isSet = value !== null; // null means "intentionally unset"

  const flags = [];
  if (isSet && isDeepStrictEqual(value, defaultValue)) flags.push('equals default: drop');
  if (isSet && defaultValue === undefined && keyPath.length === 1) {
    flags.push('not in defaults: unset-by-default key, or removed/renamed?');
  }
  if (isSet && !isApplied(value, liveValue)) flags.push('db differs: unapplied');
  if (!isSet && !isEmpty(liveValue)) {
    flags.push('null still has a value in the db: unapplied, or Orca repopulated it');
  }

  const note = flags.length ? ` -> ${flags.join('; ')}` : '';
  console.log(`${key} ours=${preview(value)} default=${preview(defaultValue)}${note}`);
}

console.log('\n# Live drift: set in the db, not in settings.jsonc');
for (const [keyPath, liveValue] of settingLeaves(live)) {
  const key = keyPath.join('.');
  const defaultValue = getPath(defaults, keyPath);
  const skip =
    INTERNAL_KEY.test(key) ||
    getPath(ours, keyPath) !== undefined ||
    isDeepStrictEqual(liveValue, defaultValue) ||
    (defaultValue === undefined && isEmpty(liveValue));
  if (!skip) console.log(`${key} live=${preview(liveValue)} default=${preview(defaultValue)}`);
}

console.log('\n# New default keys absent from the db');
for (const [keyPath, defaultValue] of settingLeaves(defaults)) {
  const key = keyPath.join('.');
  if (!INTERNAL_KEY.test(key) && getPath(live, keyPath) === undefined) {
    console.log(`${key} default=${preview(defaultValue)}`);
  }
}
