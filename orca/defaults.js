// Prints Orca's built-in default settings as JSON, to diff against the profile db.
// Usage: node orca/defaults.js <extracted app.asar dir>
// Extract with: npx @electron/asar extract /Applications/Orca.app/Contents/Resources/app.asar <dir>

const Module = require('module');
const os = require('os');
const path = require('path');

const [dir] = process.argv.slice(2);
if (!dir) {
  console.error('usage: node orca/defaults.js <extracted app.asar dir>');
  process.exit(1);
}

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

const { getDefaultSettings } = require(path.resolve(dir, 'out/shared/constants.js'));

// JSON.stringify would silently drop a default built from the stub, so fail instead.
const noStub = (key, value) => {
  if (value === stub) throw new Error(`default "${key}" came from a stubbed module`);
  return value;
};

console.log(JSON.stringify(getDefaultSettings(os.homedir()), noStub, 2));
