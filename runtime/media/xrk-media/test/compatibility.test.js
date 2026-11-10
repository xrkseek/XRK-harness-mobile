import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { evaluatePluginCompatibility } from '@xrkseek/harness-cli-app-boot';

const manifest = JSON.parse(await readFile(new URL('../package.json', import.meta.url)));
test('host accepts both declared XRK versions without exemptions and rejects untested versions', () => {
  for (const version of ['0.2.1-rc.4', '0.2.2-rc.1']) {
    assert.equal(evaluatePluginCompatibility(manifest, {}, version), undefined);
  }
  const original = structuredClone(manifest);
  for (const name of Object.keys(original.peerDependencies)) {
    if (name.startsWith('@xrkseek/harness-cli-')) original.peerDependencies[name] = '0.2.1-rc.4';
  }
  assert.equal(evaluatePluginCompatibility(original, {}, '0.2.2-rc.1').exempted, false);
  assert.equal(evaluatePluginCompatibility(manifest, {}, '0.2.2-rc.2').exempted, false);
});

const prepare = fileURLToPath(new URL('./headless-v2/prepare.mjs', import.meta.url));
for (const version of ['0.2.1-rc.4', '0.2.2-rc.1']) {
  test(`compatibility prefix preserves pinned XRK ${version}`, async t => {
    const root = await mkdtemp(join(tmpdir(), 'media-compat-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const out = join(root, 'deps');
    execFileSync(process.execPath, [prepare, '--out', out, '--engine-version', version]);
    const lock = JSON.parse(await readFile(join(out, 'package-lock.json')));
    const manifest = JSON.parse(await readFile(join(out, 'package.json')));
    const identity = JSON.parse(await readFile(join(out, 'test-inputs.json')));
    assert.equal(manifest.dependencies['@xrkseek/harness-cli'], version);
    assert.equal(lock.packages['node_modules/@xrkseek/harness-cli'].version, version);
    assert.equal(lock.packages['node_modules/@xrkseek/harness-cli-llm-mock-server'].version, version);
    assert.equal(identity.dsh, version);
    for (const [path, pkg] of Object.entries(lock.packages)) {
      if (path.split('/').at(-1)?.startsWith('dsh-')) assert.equal(pkg.version, version, path);
    }
    const source = new URL('../../../locks/dsh-' + version + '/package-lock.json', import.meta.url);
    const original = JSON.parse(await readFile(source));
    for (const [path, pkg] of Object.entries(original.packages)) {
      if (path) assert.deepEqual(lock.packages[path], pkg, path);
    }
    assert.throws(() => execFileSync(process.execPath, [prepare, '--out', out, '--engine-version', version], { stdio: 'pipe' }));
  });
}
