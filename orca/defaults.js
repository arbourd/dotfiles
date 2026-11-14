// Prints Orca's built-in default settings as JSON, to diff against the profile db.
// Usage: node orca/defaults.js [extracted app.asar dir]
// With no dir, extracts /Applications/Orca.app's app.asar into a temp dir first, and removes it after.

const { execFileSync } = require('child_process');
const fs = require('fs');
const Module = require('module');
const os = require('os');
const path = require('path');

const ASAR_PATH = '/Applications/Orca.app/Contents/Resources/app.asar';

// Absorbs any property access, call, or construction.
// shortcut: string conversion yields '' (modules do it at import), so an interpolated default
// would print wrong instead of failing; revisit if one appears.
const stub = new Proxy(function () {}, {
  get: (_, key) => (key === Symbol.toPrimitive ? () => '' : stub),
  apply: () => stub,
  construct: () => stub,
});

// app.asar imports npm modules (zod etc.) it doesn't ship; getDefaultSettings doesn't use them.
function stubMissingModules() {
  const originalLoad = Module._load;
  Module._load = function (request, ...rest) {
    try {
      return originalLoad.call(this, request, ...rest);
    } catch (error) {
      // Only when the request itself is missing, not a require inside a real package.
      const isMissing =
        error?.code === 'MODULE_NOT_FOUND' && error.message.startsWith(`Cannot find module '${request}'`);
      if (isMissing && !request.startsWith('.') && !path.isAbsolute(request)) return stub;
      throw error;
    }
  };
}

// JSON.stringify would silently drop a stubbed default, so fail instead.
function rejectStub(key, value) {
  if (value === stub) throw new Error(`default "${key}" came from a stubbed module`);
  return value;
}

function extractAsar(dir) {
  execFileSync('npx', ['--yes', '@electron/asar', 'extract', ASAR_PATH, dir], {
    stdio: ['ignore', 'ignore', 'inherit'],
  });
}

function printDefaults(dir) {
  const { getDefaultSettings } = require(path.resolve(dir, 'out/shared/constants.js'));
  console.log(JSON.stringify(getDefaultSettings(os.homedir()), rejectStub, 2));
}

const givenDir = process.argv[2] || null; // '' means no dir
const dir = givenDir ?? fs.mkdtempSync(path.join(os.tmpdir(), 'orca-asar-'));

stubMissingModules();
try {
  if (!givenDir) extractAsar(dir);
  printDefaults(dir);
} finally {
  if (!givenDir) fs.rmSync(dir, { recursive: true, force: true });
}
