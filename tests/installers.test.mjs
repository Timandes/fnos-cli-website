import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, rmSync, chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';

const installer = fileURLToPath(new URL('../static/install.sh', import.meta.url));

// Only network access, host detection, and the npm registry are replaced.
// Real bash, tar, SHA-256, filesystem writes and installed launcher execute.
function fixture(t, {runtime = 'current', platform = 'Linux', arch = 'x86_64', installed = false, writable = true} = {}) {
  const dir = mkdtempSync(path.join(tmpdir(), 'fnos install test '));
  t.after(() => {
    chmodSync(globalPrefix, 0o755);
    chmodSync(globalRoot, 0o755);
    rmSync(dir, {recursive: true, force: true});
  });
  const home = path.join(dir, 'home with spaces');
  const globalPrefix = path.join(home, '.nvm/versions/node/v24.1.0');
  const globalRoot = path.join(globalPrefix, 'lib/node_modules');
  const bin = path.join(globalPrefix, 'bin');
  mkdirSync(bin, {recursive: true});
  mkdirSync(globalRoot, {recursive: true});
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
if [[ "$*" == "prefix --global" ]]; then echo "$FNOS_TEST_PREFIX"; exit 0; fi
if [[ "$*" == "root --global" ]]; then echo "$FNOS_TEST_PREFIX/lib/node_modules"; exit 0; fi
if [[ "$*" == "install --global fnos-cli@latest" ]]; then
  target_prefix="$FNOS_TEST_PREFIX"
elif [[ "$*" == "install --global --prefix $HOME/.local/share/fnos-cli/npm fnos-cli@latest" ]]; then
  target_prefix="$HOME/.local/share/fnos-cli/npm"
else
  exit 8
fi
[[ "$(node --version)" == v24.1.0 ]] || exit 7
[[ "\${FAIL_NPM:-}" != 1 ]] || exit 23
mkdir -p "$target_prefix/lib/node_modules/fnos-cli/bin" "$target_prefix/bin"
printf '#!/bin/bash\\nprintf "0.5.1\\\\n"\\n' > "$target_prefix/lib/node_modules/fnos-cli/bin/fnos"
printf '{"name":"fnos-cli","version":"0.5.1"}' > "$target_prefix/lib/node_modules/fnos-cli/package.json"
chmod +x "$target_prefix/lib/node_modules/fnos-cli/bin/fnos"
ln -sf ../lib/node_modules/fnos-cli/bin/fnos "$target_prefix/bin/fnos"`;
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
  if (installed) {
    const pkg = path.join(globalRoot, 'fnos-cli');
    mkdirSync(path.join(pkg, 'bin'), {recursive: true});
    writeFileSync(path.join(pkg, 'package.json'), JSON.stringify({name: 'fnos-cli', version: '0.4.0'}));
    writeFileSync(path.join(pkg, 'bin/fnos'), '#!/bin/bash\necho 0.4.0\n', {mode: 0o755});
    assert.equal(spawnSync('/bin/ln', ['-s', '../lib/node_modules/fnos-cli/bin/fnos', path.join(bin, 'fnos')]).status, 0);
  }
  if (!writable) { chmodSync(globalPrefix, 0o555); chmodSync(globalRoot, 0o555); }
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
  const env = {...process.env, HOME: home, SHELL: '/bin/bash', PATH: `${bin}:/usr/bin:/bin`, BASH_ENV: '', ENV: '', FAIL_ONCE: '', FNOS_TEST_PREFIX: globalPrefix};
  const run = (extra = {}) => spawnSync('/bin/bash', [installer], {env: {...env, ...extra}, encoding: 'utf8'});
  return {home, run, env, globalPrefix, globalRoot};
}

test('updates existing fnos in the active npm environment without a private copy or PATH edits', t => {
  const f = fixture(t, {installed: true, platform: 'Darwin', arch: 'arm64'});
  const result = f.run({FAIL_DOWNLOAD: '1'});
  assert.equal(result.status, 0, result.stderr);
  const launcher = path.join(f.globalPrefix, 'bin/fnos');
  assert.equal(spawnSync(launcher, ['--version'], {env: f.env, encoding: 'utf8'}).stdout.trim(), '0.5.1');
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/bin/fnos')));
  assert.ok(!existsSync(path.join(f.home, '.bashrc')));
  assert.equal(result.stdout.match(/^0\.5\.1$/gm)?.length, 1);
});

test('uses the active npm prefix for a first installation when it is writable', t => {
  const f = fixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(existsSync(path.join(f.globalRoot, 'fnos-cli/package.json')));
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
});

test('does not create a second installation if an existing global environment is read-only', t => {
  const f = fixture(t, {installed: true, writable: false});
  const result = f.run();
  assert.notEqual(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stderr, /权限|不可写/);
  assert.equal(JSON.parse(readFileSync(path.join(f.globalRoot, 'fnos-cli/package.json'))).version, '0.4.0');
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
});

test('can use a private installation when the global environment is read-only and fnos is absent', t => {
  const f = fixture(t, {writable: false});
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  assert.ok(existsSync(path.join(f.home, '.local/share/fnos-cli/bin/fnos')));
  assert.ok(!existsSync(path.join(f.globalRoot, 'fnos-cli')));
});

test('removes only the old installer PATH block after updating the npm-managed installation', t => {
  const f = fixture(t, {installed: true});
  const profile = path.join(f.home, '.zshrc');
  const oldBin = path.join(f.home, '.local/share/fnos-cli/bin');
  mkdirSync(oldBin, {recursive: true});
  const oldLauncher = path.join(oldBin, 'fnos');
  writeFileSync(oldLauncher, '#!/bin/bash\necho 0.3.0\n', {mode: 0o755});
  writeFileSync(profile, '# 我的配置\nexport KEEP_ME=yes\n# fnos-cli\nexport PATH="$HOME/.local/share/fnos-cli/bin:$PATH"\n# 保留结尾\n');
  const result = f.run({SHELL: '/bin/zsh', PATH: `${oldBin}:${f.env.PATH}`});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(profile, 'utf8'), '# 我的配置\nexport KEEP_ME=yes\n# 保留结尾\n');
  assert.equal(readFileSync(oldLauncher, 'utf8'), '#!/bin/bash\necho 0.3.0\n');
  assert.equal(spawnSync(path.join(f.globalPrefix, 'bin/fnos'), ['--version'], {env: f.env, encoding: 'utf8'}).stdout.trim(), '0.5.1');
});

test('leaves unrelated shell configuration byte-for-byte unchanged', t => {
  const f = fixture(t, {installed: true});
  const profile = path.join(f.home, '.zshrc');
  const original = 'export KEEP_MY_CONFIG=yes';
  writeFileSync(profile, original);
  const result = f.run({SHELL: '/bin/zsh'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(profile, 'utf8'), original);
});

test('preserves an unterminated user line while removing a legacy PATH block', t => {
  const f = fixture(t, {installed: true});
  const profile = path.join(f.home, '.zshrc');
  writeFileSync(profile, '# fnos-cli\nexport PATH="$HOME/.local/share/fnos-cli/bin:$PATH"\nexport KEEP_ME=yes');
  assert.equal(f.run({SHELL: '/bin/zsh'}).status, 0);
  assert.equal(readFileSync(profile, 'utf8'), 'export KEEP_ME=yes');
});

test('preserves customized fish configuration and adds the native npm bin only once', t => {
  const f = fixture(t);
  const customPrefix = path.join(f.home, 'custom npm prefix');
  mkdirSync(path.join(customPrefix, 'lib/node_modules'), {recursive: true});
  const fishDir = path.join(f.home, '.config/fish/conf.d');
  mkdirSync(fishDir, {recursive: true});
  const profile = path.join(fishDir, 'fnos-cli.fish');
  const original = '# 用户自己的配置\nset -gx KEEP_ME yes';
  writeFileSync(profile, original);
  const env = {SHELL: '/usr/bin/fish', FNOS_TEST_PREFIX: customPrefix};
  const first = f.run(env);
  assert.equal(first.status, 0, first.stderr);
  assert.ok(readFileSync(profile, 'utf8').startsWith(original + '\n'));
  assert.match(first.stdout, /fish_add_path/);
  assert.doesNotMatch(first.stdout, /export PATH=/);
  assert.equal(f.run(env).status, 0);
  assert.equal(readFileSync(profile, 'utf8').match(/fish_add_path/g)?.length, 1);
});

test('migrates a marked private fish PATH block while preserving user content', t => {
  const f = fixture(t, {installed: true});
  const fishDir = path.join(f.home, '.config/fish/conf.d');
  mkdirSync(fishDir, {recursive: true});
  const profile = path.join(fishDir, 'fnos-cli.fish');
  writeFileSync(profile, `# 用户配置\n# fnos-cli\nfish_add_path "${f.home}/.local/share/fnos-cli/bin"\nset -gx KEEP_ME yes`);
  const result = f.run({SHELL: '/usr/bin/fish'});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(profile, 'utf8'), '# 用户配置\nset -gx KEEP_ME yes');
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
});

test('reports a shadowing old command without editing unowned PATH settings', t => {
  const f = fixture(t, {installed: true});
  const oldBin = path.join(f.home, '.local/share/fnos-cli/bin');
  mkdirSync(oldBin, {recursive: true});
  writeFileSync(path.join(oldBin, 'fnos'), '#!/bin/bash\necho 0.3.0\n', {mode: 0o755});
  const profile = path.join(f.home, '.zshrc');
  const original = 'export PATH="$HOME/.local/share/fnos-cli/bin:$PATH"\n';
  writeFileSync(profile, original);
  const result = f.run({SHELL: '/bin/zsh', PATH: `${oldBin}:${f.env.PATH}`});
  assert.equal(result.status, 0, result.stderr);
  assert.equal(readFileSync(profile, 'utf8'), original);
  assert.doesNotMatch(result.stdout, /当前环境可以直接使用/);
  assert.match(result.stdout, /PATH/);
});

test('a failed npm update leaves the existing CLI and shell configuration intact', t => {
  const f = fixture(t, {installed: true});
  const profile = path.join(f.home, '.zshrc');
  const original = '# fnos-cli\nexport PATH="$HOME/.local/share/fnos-cli/bin:$PATH"\n';
  writeFileSync(profile, original);
  const result = f.run({SHELL: '/bin/zsh', FAIL_NPM: '1'});
  assert.notEqual(result.status, 0);
  assert.equal(readFileSync(profile, 'utf8'), original);
  assert.equal(JSON.parse(readFileSync(path.join(f.globalRoot, 'fnos-cli/package.json'))).version, '0.4.0');
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
});

test('respects a custom npm prefix and enables its native command when missing from PATH', t => {
  const f = fixture(t);
  const customPrefix = path.join(f.home, 'custom npm prefix');
  mkdirSync(path.join(customPrefix, 'lib/node_modules'), {recursive: true});
  const result = f.run({FNOS_TEST_PREFIX: customPrefix});
  assert.equal(result.status, 0, result.stderr);
  assert.ok(existsSync(path.join(customPrefix, 'lib/node_modules/fnos-cli/package.json')));
  const resolved = spawnSync('/bin/bash', ['-c', '. "$HOME/.bashrc"; command -v fnos'], {env: f.env, encoding: 'utf8'});
  assert.equal(resolved.status, 0, resolved.stderr);
  assert.equal(resolved.stdout.trim(), path.join(customPrefix, 'bin/fnos'));
  assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
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

test('repeated private installation writes the shell PATH only once', t => {
  const f = fixture(t, {runtime: 'missing'});
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
  assert.doesNotMatch(result.stdout, /安装完成/);
});

for (const extra of [{FAIL_DOWNLOAD: '1'}, {BAD_HASH: '0'.repeat(64)}]) {
  test(`download or integrity failure stops before npm: ${Object.keys(extra)[0]}`, t => {
    const f = fixture(t, {runtime: 'missing'});
    const result = f.run(extra);
    assert.notEqual(result.status, 0);
    assert.ok(!existsSync(path.join(f.home, '.local/share/fnos-cli/npm')));
    assert.doesNotMatch(result.stdout, /安装完成/);
  });
}

test('unsupported architecture fails with an actionable error before downloading', t => {
  const f = fixture(t, {runtime: 'missing', arch: 'riscv64'});
  const result = f.run();
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /架构/);
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
  const f = fixture(t, {runtime: 'missing'});
  const zdotdir = path.join(f.home, 'zsh config');
  assert.equal(f.run({SHELL: '/bin/zsh', ZDOTDIR: zdotdir}).status, 0);
  assert.match(readFileSync(path.join(zdotdir, '.zshrc'), 'utf8'), /export PATH=/);
  assert.ok(!existsSync(path.join(f.home, '.zshrc')));
});
