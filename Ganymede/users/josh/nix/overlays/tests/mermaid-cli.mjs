import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const { Interceptor } = await import(pathToFileURL(process.env.MERMAID_INTERCEPTOR));
const root = await mkdtemp(path.join(tmpdir(), 'mermaid-containment-'));
const requestUrl = file => `https://mermaid-cli-intercept.invalid${file}`;

try {
  const allowed = path.join(root, 'allowed');
  await mkdir(allowed);
  await mkdir(path.join(root, 'allowed-sibling'));
  await writeFile(path.join(allowed, 'seed.js'), '');
  await writeFile(path.join(allowed, 'valid.txt'), 'allowed marker');
  await writeFile(path.join(root, 'private.txt'), 'private marker');
  await writeFile(path.join(root, 'allowed-sibling', 'private.txt'), 'private marker');
  await symlink(path.join(root, 'private.txt'), path.join(allowed, 'escape.txt'));
  await symlink(path.join(allowed, 'valid.txt'), path.join(allowed, 'internal.txt'));

  const interceptor = new Interceptor();
  await interceptor.fileUrlToInterceptUrl(pathToFileURL(path.join(allowed, 'seed.js')));

  for (const name of ['valid.txt', 'internal.txt']) {
    assert.equal((await interceptor.interceptUrlToFileUrl(requestUrl(path.join(allowed, name)))).href,
      pathToFileURL(path.join(allowed, 'valid.txt')).href);
  }

  for (const target of [root, allowed, path.join(root, 'private.txt'),
    path.join(root, 'allowed-sibling', 'private.txt'), path.join(allowed, 'escape.txt')]) {
    await assert.rejects(interceptor.interceptUrlToFileUrl(requestUrl(target)), /not in an allowed directory/);
  }

  let body;
  await interceptor.interceptRequestHandler({
    url: () => requestUrl(path.join(allowed, 'valid.txt')),
    respond: response => { body = response.body.toString(); },
    abort: () => assert.fail('Allowed file was blocked'),
    continue: () => assert.fail('Local request escaped interception'),
  });
  assert.equal(body, 'allowed marker');
  console.log('Mermaid containment checks passed');
} finally {
  await rm(root, { recursive: true, force: true });
}
