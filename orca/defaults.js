// Prints Orca's built-in default settings as JSON, to diff against the profile db.
// Usage: node orca/defaults.js [extracted app.asar dir]
// With no dir, extracts /Applications/Orca.app's app.asar into a temp dir first, and removes it after.

const { execFileSync } = require('child_process');
const fs = require('fs');
const Module = require('module');
const os = require('os');
const path = require('path');

let [dir] = process.argv.slice(2);
const extracted = !dir;
if (extracted) dir = fs.mkdtempSync(path.join(os.tmpdir(), 'orca-asar-'));

// app.asar imports npm modules (zod etc.) it doesn't ship; getDefaultSettings doesn't use them.
const stub = new Proxy(function () {}, {
  get: (_, key) => (key === Symbol.toPrimitive ? () => '' : stub),
  apply: () => stub,
  construct: () => stub,
});

const load = Module._load;
Module._load = function (request, ...rest) {
  try {
    return load.call(this, request, ...rest);
  } catch (e) {
    // Stub only when the request itself is missing, not a broken require inside a real package.
    const missing = e?.code === 'MODULE_NOT_FOUND' && e.message.startsWith(`Cannot find module '${request}'`);
    if (missing && !request.startsWith('.')) return stub;
    throw e;
  }
};

// JSON.stringify would silently drop a default built from the stub, so fail instead.
const noStub = (key, value) => {
  if (value === stub) throw new Error(`default "${key}" came from a stubbed module`);
  return value;
};

try {
  if (extracted) {
    const asar = '/Applications/Orca.app/Contents/Resources/app.asar';
    execFileSync('npx', ['--yes', '@electron/asar', 'extract', asar, dir], { stdio: ['ignore', 'ignore', 'inherit'] });
  }
  const { getDefaultSettings } = require(path.resolve(dir, 'out/shared/constants.js'));
  console.log(JSON.stringify(getDefaultSettings(os.homedir()), noStub, 2));
} finally {
  if (extracted) fs.rmSync(dir, { recursive: true, force: true });
}
