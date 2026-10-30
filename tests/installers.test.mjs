import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const installer = fileURLToPath(new URL('../static/install.sh', import.meta.url));

// Only network access, host detection, and the npm registry are replaced.
// Real bash, tar, SHA-256, filesystem writes and installed launcher execute.
function fixture(t, {runtime = 'current', platform = 'Linux', arch = 'x86_64'} = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'fnos install test '));
  t.after(() => rmSync(dir, {recursive: true, force: true}));
  const home = path.join(dir, 'home with spaces');
  const bin = path.join(dir, 'tools');
  mkdirSync(home);
  mkdirSync(bin);
  const script = (name, content) => writeFileSync(path.join(bin, name), `#!/bin/bash\n${content}\n`, {mode: 0o755});
  const nodeBody = `
if [[ "$1" == --version ]]; then echo v24.1.0; exit 0; fi
if [[ "$1" == */fnos-cli/bin/fnos ]]; then
  [[ -f "$1" ]] || exit 9
  echo 0.5.1
  exit 0
fi
exit 2`;
  const npmBody = `
if [[ "$1" == --version ]]; then echo 11.0.0; exit 0; fi
[[ "$*" == "install --global --prefix $HOME/.local/share/fnos-cli/npm fnos-cli@latest" ]] || exit 8
[[ "$(node --version)" == v24.1.0 ]] || exit 7
[[ "\${FAIL_NPM:-}" != 1 ]] || exit 23
mkdir -p "$HOME/.local/share/fnos-cli/npm/lib/node_modules/fnos-cli/bin"
touch "$HOME/.local/share/fnos-cli/npm/lib/node_modules/fnos-cli/bin/fnos"`;
  const runtimeName = `node-v24.1.0-${platform === 'Darwin' ? 'darwin' : 'linux'}-${arch === 'arm64' || arch === 'aarch64' ? 'arm64' : 'x64'}`;
  const payload = path.join(dir, 'payload', runtimeName, 'bin');
  mkdirSync(payload, {recursive: true});
  writeFileSync(path.join(payload, 'node'), `#!/bin/bash\n${nodeBody}\n`, {mode: 0o755});
  writeFileSync(path.join(payload, 'npm'), `#!/bin/bash\n${npmBody}\n`, {mode: 0o755});
  const archive = path.join(dir, 'node.tar.gz');
  assert.equal(spawnSync('/usr/bin/tar', ['-czf', archive, '-C', path.join(dir, 'payload'), runtimeName]).status, 0);
  const hash = createHash('sha256').update(readFileSync(archive)).digest('hex');
  script('uname', `if [[ "$1" == -s ]]; then echo '${platform}'; else echo '${arch}'; fi`);
  script('node', runtime === 'current' ? nodeBody : `if [[ "$1" == --version ]]; then echo '${runtime === 'old' ? 'v18.16.0' : 'v0.0.0'}'; exit 0; fi\nexit 127`);
  script('npm', runtime === 'current' ? npmBody : 'exit 127');
  script('curl', `
if [[ "$FAIL_ONCE" == 1 && ! -e "$HOME/download-attempted" ]]; then touch "$HOME/download-attempted"; exit 92; fi
[[ "\${FAIL_DOWNLOAD:-}" != 1 ]] || exit 22
url=''; out=''
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    https:*) url="$1"; shift ;;
    *) shift ;;
  esac
done
case "$url" in
  https://nodejs.org/dist/latest-v24.x/SHASUMS256.txt)
    printf '%s  node-v24.1.0-%s-%s.tar.gz\\n' "\${BAD_HASH:-${hash}}" '${platform === 'Darwin' ? 'darwin' : 'linux'}' '${arch === 'arm64' || arch === 'aarch64' ? 'arm64' : 'x64'}' > "$out" ;;
  https://nodejs.org/dist/v24.1.0/node-v24.1.0-*.tar.gz) cp '${archive}' "$out" ;;
  *) exit 17 ;;
esac`);
  const env = {...process.env, HOME: home, SHELL: '/bin/bash', PATH: `${bin}:/usr/bin:/bin`, BASH_ENV: '', ENV: '', FAIL_ONCE: ''};
  const run = (extra = {}) => spawnSync('/bin/bash', [installer], {env: {...env, ...extra}, encoding: 'utf8'});
  return {home, run, env};
}

test('reuses a compatible runtime and installs a working launcher in a path with spaces', t => {
  const f = fixture(t);
  const result = f.run({FAIL_DOWNLOAD: '1'});
  assert.equal(result.status, 0, result.stderr);
  const launcher = path.join(f.home, '.local/share/fnos-cli/bin/fnos');
  assert.equal(spawnSync(launcher, ['--version'], {env: f.env, encoding: 'utf8'}).stdout.trim(), '0.5.1');
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/node-v24.1.0-linux-x64')));
});

for (const runtime of ['missing', 'old']) {
  test(`automatically provisions Node/npm when the runtime is ${runtime}`, t => {
    const f = fixture(t, {runtime});
    const result = f.run();
    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /0\.5\.1/);
    assert.ok(existsSync(path.join(f.home, '.local/share/fnos-cli/node-v24.1.0-linux-x64/bin/node')));
  });
}

test('repeated installation writes the shell PATH only once', t => {
  const f = fixture(t);
  assert.equal(f.run().status, 0);
  assert.equal(f.run().status, 0);
  assert.equal(readFileSync(path.join(f.home, '.bashrc'), 'utf8').match(/export PATH=/g)?.length, 1);
});

test('a fresh terminal reuses the previously downloaded runtime without network download', t => {
  const f = fixture(t, {runtime: 'missing'});
  assert.equal(f.run().status, 0);
  const result = f.run({FAIL_DOWNLOAD: '1'});
  assert.equal(result.status, 0, result.stderr);
});

test('a transient download protocol failure is retried', t => {
  const f = fixture(t, {runtime: 'missing'});
  const result = f.run({FAIL_ONCE: '1'});
  assert.equal(result.status, 0, result.stderr);
});

test('failed npm installation exits nonzero and never reports success', t => {
  const f = fixture(t);
  const result = f.run({FAIL_NPM: '1'});
  assert.notEqual(result.status, 0);
  assert.doesNotMatch(result.stdout, /Installation complete/);
});

for (const extra of [{FAIL_DOWNLOAD: '1'}, {BAD_HASH: '0'.repeat(64)}]) {
  test(`download or integrity failure stops before npm: ${Object.keys(extra)[0]}`, t => {
    const f = fixture(t, {runtime: 'missing'});
    const result = f.run(extra);
    assert.notEqual(result.status, 0);
    assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
    assert.doesNotMatch(result.stdout, /Installation complete/);
  });
}

test('unsupported architecture fails with an actionable error before downloading', t => {
  const f = fixture(t, {runtime: 'missing', arch: 'riscv64'});
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /architecture/i);
});

for (const [platform, arch] of [['Darwin', 'arm64'], ['Darwin', 'x86_64'], ['Linux', 'aarch64']]) {
  test(`selects a usable runtime for ${platform} ${arch}`, t => {
    const f = fixture(t, {runtime: 'missing', platform, arch});
    const result = f.run();
    assert.equal(result.status, 0, result.stderr);
    const launcher = path.join(f.home, '.local/share/fnos-cli/bin/fnos');
    assert.equal(spawnSync(launcher, ['--version'], {env: f.env, encoding: 'utf8'}).stdout.trim(), '0.5.1');
  });
}

test('zsh installs PATH under ZDOTDIR instead of the default home', t => {
  const f = fixture(t);
  const zdotdir = path.join(f.home, 'zsh config');
  assert.equal(f.run({SHELL: '/bin/zsh', ZDOTDIR: zdotdir}).status, 0);
  assert.match(readFileSync(path.join(zdotdir, '.zshrc'), 'utf8'), /export PATH=/);
  assert.ok(!existsSync(path.join(f.home, '.zshrc')));
});
