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

function compare(flag, onRequestArgs) {
  const wanted = brew('bundle', 'list', `--${flag}`, `--file=${BREWFILE}`);
  const wantedShort = new Set(wanted.map(short));

  // Every name each installed package answers to: its name, full name and aliases, so kubectl matches kubernetes-cli.
  const installed = JSON.parse(run('info', '--json=v2', '--installed'));
  const ids = new Map(
    (flag === 'cask' ? installed.casks : installed.formulae).map((item) => {
      const names = flag === 'cask' ? [item.token, item.full_token, ...item.old_tokens] : [item.name, item.full_name, ...item.aliases, ...item.oldnames];
      return [item.token ?? item.name, new Set(names.map(short))];
    }),
  );

  const extra = brew(...onRequestArgs).filter((name) => ![...ids.get(short(name))].some((id) => wantedShort.has(id)));
  const missing = wanted.filter((name) => ![...ids.values()].some((names) => names.has(short(name))));
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
