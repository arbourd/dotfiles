// Compares the Brewfile in the repo root with what Homebrew has installed, for formulae and casks.
// Usage: bun .agents/skills/homebrew-drift/scripts/compare.js   (read-only)
// BREW overrides the brew binary, for tests.

const { execFileSync } = require('child_process');
const path = require('path');

const ROOT = path.join(__dirname, '../../../..');
const BREWFILE = path.join(ROOT, 'Brewfile');
const BREW = process.env.BREW || 'brew';

const fail = (message) => {
  console.error(`compare.js: ${message}`);
  process.exit(1);
};

const run = (...args) => {
  try {
    return execFileSync(BREW, args, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe'],
      env: { ...process.env, HOMEBREW_NO_AUTO_UPDATE: '1', HOMEBREW_NO_ENV_HINTS: '1', HOMEBREW_BUNDLE_NO_LOCK: '1' },
    });
  } catch (error) {
    fail(`brew ${args.join(' ')}: ${error.stderr?.toString().trim() || error.message}`);
  }
};

const brew = (...args) => run(...args).split('\n').map((line) => line.trim()).filter(Boolean);

// arbourd/tap/go and go are the same package for this comparison, so match on the last segment.
const short = (name) => name.split('/').pop();

// Maps each Brewfile entry to the canonical short name Homebrew installs it as, so aliases like kubectl for
// kubernetes-cli match. Casks and formulae differ in their JSON keys.
function canonical(flag, entries) {
  if (!entries.length) return new Map();
  let info;
  try {
    info = JSON.parse(run('info', '--json=v2', `--${flag}`, ...entries));
  } catch (error) {
    if (error instanceof SyntaxError) fail(`brew info --${flag}: unparseable output`);
    throw error;
  }
  const items = (flag === 'cask' ? info.casks : info.formulae).map((item) =>
    flag === 'cask'
      ? { name: item.token, ids: [item.token, item.full_token, ...(item.old_tokens ?? [])] }
      : { name: item.name, ids: [item.name, item.full_name, ...(item.aliases ?? []), ...(item.oldnames ?? [])] },
  );
  return new Map(entries.map((entry) => [entry, items.find((item) => item.ids.some((id) => id === entry || short(id) === short(entry)))?.name ?? short(entry)]));
}

function compare(flag, installedOnRequest) {
  const wanted = brew('bundle', 'list', `--${flag}`, `--file=${BREWFILE}`);
  const names = canonical(flag, wanted);
  const wantedShort = new Set(names.values());
  const installed = brew(...installedOnRequest);
  const installedShort = new Set(brew('list', `--${flag}`, '-1', '--full-name').map(short));

  const extra = installed.filter((name) => !wantedShort.has(short(name)));
  const missing = wanted.filter((name) => !installedShort.has(names.get(name)));
  return { extra, missing };
}

const formula = compare('formula', ['leaves', '--installed-on-request']);
const cask = compare('cask', ['list', '--cask', '-1', '--full-name']);

const section = (title, rows) => [`## ${title}`, ...(rows.length ? rows : ['(none)'])];
console.log(
  [
    `# Brewfile → brew (${BREWFILE})`,
    '',
    ...section('Not in Brewfile', [...formula.extra.map((n) => `formula ${n}`), ...cask.extra.map((n) => `cask ${n}`)]),
    '',
    ...section('Not installed', [...formula.missing.map((n) => `formula ${n}`), ...cask.missing.map((n) => `cask ${n}`)]),
  ].join('\n'),
);
