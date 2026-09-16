// node --test tooling/bind/
//
// Every case runs the REAL bind over the two committed fixtures — one
// `terraform output -json` document per stack, carrying every output both
// stacks declare. The fixtures are the contract's denominator: an output added
// to a stack without a DISPOSITIONS row is what `unknown output refused` is
// for, and adding it to a fixture without a row reddens `both fixtures bind`.

import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { BindError, DISPOSITIONS, Disposition, assertOutsideWorkTree, bind } from './bind-outputs.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SCRIPT = path.join(HERE, 'bind-outputs.mjs');
const fixture = (cloud) => JSON.parse(fs.readFileSync(path.join(HERE, 'fixtures', `${cloud}.output.json`), 'utf8'));

/** Every string that sits under a `sensitive: true` output, recursively. */
function sensitiveStrings(doc) {
  const out = [];
  const walk = (v) => {
    if (typeof v === 'string') out.push(v);
    else if (v && typeof v === 'object') Object.values(v).forEach(walk);
  };
  for (const entry of Object.values(doc)) if (entry.sensitive) walk(entry.value);
  return out.filter((s) => s !== '');
}

for (const cloud of ['digitalocean', 'azure']) {
  test(`${cloud}: the fragment carries no sensitive value and the externals carry the credentials`, () => {
    const doc = fixture(cloud);
    const { fragment, externals, report } = bind(doc);
    const fragmentText = JSON.stringify(fragment);
    for (const secret of sensitiveStrings(doc)) {
      assert.ok(!fragmentText.includes(secret), `sensitive value reached the fragment: ${secret}`);
    }
    assert.equal(fragment.postgres.directHost, doc.substrate.value.postgres_host);
    assert.equal(fragment.postgres.directPort, doc.substrate.value.postgres_port);
    assert.equal(fragment.keycloak.issuer, `https://id.acme.example/realms/acme-prod`);
    assert.equal(externals['keycloak-identity-client-secret'], 'FIXTURE-IDENTITY-CLIENT-SECRET');
    // Operator-only credentials are named, never written.
    const externalsText = JSON.stringify(externals);
    assert.ok(!externalsText.includes('FIXTURE-ADMIN-PASSWORD'), 'postgres_uri must never be written');
    assert.ok(!externalsText.includes('KUBE-TOKEN') && !externalsText.includes('CLIENT-KEY'), 'kubeconfig must never be written');
    assert.ok(report.operator.some((l) => l.startsWith('postgres_uri:')), 'postgres_uri is reported as an operator step');
    assert.ok(report.operator.some((l) => l.startsWith('kubeconfig_raw:')));
  });
}

test('digitalocean: the null app role and cache are omitted loudly, not refused', () => {
  const { fragment, report } = bind(fixture('digitalocean'));
  assert.equal(fragment.postgres.role, undefined);
  assert.equal(fragment.redis, undefined);
  assert.ok(report.omitted.some((l) => l.startsWith('postgres.role ← substrate.postgres_app_role')));
  assert.ok(report.omitted.some((l) => l.startsWith('external redis-password ← redis_primary_key')));
});

test('azure: the app role, the cache and the redis key bind; blob and role passwords are classified, not written', () => {
  const doc = fixture('azure');
  const { fragment, externals, report } = bind(doc);
  assert.equal(fragment.postgres.role, 'acme_prod_app');
  assert.equal(fragment.redis.host, doc.substrate.value.redis_host);
  assert.equal(fragment.redis.port, 6380);
  assert.equal(externals['redis-password'], 'FIXTURE-REDIS-KEY');
  assert.deepEqual(Object.keys(externals).sort(), ['keycloak-identity-client-secret', 'redis-password']);
  assert.ok(report.operator.some((l) => l.startsWith('postgres_role_passwords:')));
  assert.ok(report.operator.some((l) => l.startsWith('blob_primary_access_key:')));
  assert.ok(report.ignored.some((l) => l.startsWith('substrate.blob_endpoint:')));
});

test('an unknown output is refused by name', () => {
  const doc = fixture('digitalocean');
  doc.brand_new_thing = { sensitive: false, type: 'string', value: 'x' };
  assert.throws(() => bind(doc), (e) => e instanceof BindError && /unknown stack output\(s\): brand_new_thing/.test(e.message));
  const doc2 = fixture('digitalocean');
  doc2.substrate.value.brand_new_key = 'x';
  assert.throws(() => bind(doc2), /unknown stack output\(s\): substrate.brand_new_key/);
});

test('a required output the document lacks is refused naming the stack output', () => {
  const doc = fixture('digitalocean');
  delete doc.realm_client_secrets;
  assert.throws(() => bind(doc), /required stack output 'realm_client_secrets' is absent/);
  const doc2 = fixture('digitalocean');
  delete doc2.substrate;
  assert.throws(() => bind(doc2), /binding contract lacks 'substrate.postgres_host'/);
});

test('a required output that is null is refused unless declared consumed', () => {
  const doc = fixture('digitalocean');
  doc.substrate.value.postgres_host = null;
  assert.throws(() => bind(doc), /stack output 'substrate.postgres_host' is null, and secret-inputs postgres.directHost needs it/);
  const { fragment, report } = bind(doc, { consumed: ['substrate.postgres_host'] });
  assert.equal(fragment.postgres.directHost, undefined);
  assert.ok(report.omitted.some((l) => l.includes('declared --consumed')));
  assert.throws(() => bind(doc, { consumed: ['not_an_output'] }), /--consumed names 'not_an_output'/);
});

test('a sensitive output routed to the fragment is refused whatever the table says', () => {
  const doc = fixture('digitalocean');
  doc.postgres_host.sensitive = true; // top-level is ignored; the map is what binds, so mark via a fragment-routed output instead
  const doc2 = fixture('azure');
  doc2.redis_primary_key.sensitive = false;
  assert.throws(() => bind(doc2), /'redis_primary_key' is not marked sensitive but the table routes it to the externals file/);
  // The map itself marked sensitive is refused outright.
  const doc3 = fixture('digitalocean');
  doc3.substrate.sensitive = true;
  assert.throws(() => bind(doc3), /output substrate is marked sensitive/);
  bind(doc); // the ignored duplicate's flag changes nothing
});

test('the identity client is selected by key and a PUBLIC client is refused', () => {
  const doc = fixture('digitalocean');
  assert.throws(() => bind(doc, { identityClient: 'web' }), /realm_client_secrets\['web'\] is empty/);
  assert.throws(() => bind(doc, { identityClient: 'nope' }), /none is 'nope' — pass --identity-client/);
  doc.realm_client_secrets.value = { platform: 'S' };
  assert.equal(bind(doc, { identityClient: 'platform' }).externals['keycloak-identity-client-secret'], 'S');
});

test('every table row has a closed-set disposition and every fixture output has a row', () => {
  const known = new Set(Object.values(Disposition));
  for (const [name, row] of Object.entries(DISPOSITIONS)) assert.ok(known.has(row.disposition), `${name}: ${row.disposition}`);
  for (const cloud of ['digitalocean', 'azure']) {
    const doc = fixture(cloud);
    for (const name of Object.keys(doc)) {
      if (name === 'substrate') for (const k of Object.keys(doc.substrate.value)) assert.ok(`substrate.${k}` in DISPOSITIONS, `substrate.${k}`);
      else assert.ok(name in DISPOSITIONS, name);
    }
  }
});

test('an externals path inside a git work tree is refused; one outside is not', () => {
  const inside = path.join(HERE, 'externals.json');
  assert.throws(() => assertOutsideWorkTree(inside), /inside a git work tree/);
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'bind-outside-'));
  try {
    assertOutsideWorkTree(path.join(outside, 'externals.json'));
  } finally {
    fs.rmSync(outside, { recursive: true, force: true });
  }
  // An unverifiable answer refuses too — git failing for any reason but "not a repository".
  assert.throws(
    () => assertOutsideWorkTree(path.join(os.tmpdir(), 'x.json'), () => { const e = new Error('boom'); e.status = 1; throw e; }),
    /cannot verify/,
  );
  assert.throws(() => assertOutsideWorkTree('/nonexistent-dir-xyz/x.json'), /directory does not exist/);
});

test('CLI: writes the fragment as YAML and the externals at 0600, and exits 1 on refusal', () => {
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'bind-cli-'));
  try {
    const fragmentPath = path.join(outside, 'fragment.yaml');
    const externalsPath = path.join(outside, 'externals.json');
    const run = spawnSync(process.execPath, [SCRIPT, '--from', path.join(HERE, 'fixtures', 'azure.output.json'), '--secret-inputs', fragmentPath, '--externals', externalsPath], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    const yamlText = fs.readFileSync(fragmentPath, 'utf8');
    assert.match(yamlText, /^postgres:\n  directHost: "acme-prod-pg\.postgres\.database\.azure\.com"\n  directPort: "5432"\n  role: "acme_prod_app"\n/m);
    assert.match(yamlText, /^keycloak:\n  issuer: "https:\/\/id\.acme\.example\/realms\/acme-prod"\n/m);
    assert.ok(!yamlText.includes('FIXTURE'), 'no fixture credential in the fragment');
    assert.equal(fs.statSync(externalsPath).mode & 0o777, 0o600);
    assert.deepEqual(JSON.parse(fs.readFileSync(externalsPath, 'utf8')), { 'keycloak-identity-client-secret': 'FIXTURE-IDENTITY-CLIENT-SECRET', 'redis-password': 'FIXTURE-REDIS-KEY' });
    assert.match(run.stderr, /operator step/);

    const refused = spawnSync(process.execPath, [SCRIPT, '--from', path.join(HERE, 'fixtures', 'azure.output.json'), '--externals', path.join(HERE, 'externals.json')], { encoding: 'utf8' });
    assert.equal(refused.status, 1);
    assert.match(refused.stderr, /inside a git work tree/);
    assert.ok(!fs.existsSync(path.join(HERE, 'externals.json')));

    // stdin path
    const piped = spawnSync(process.execPath, [SCRIPT, '--secret-inputs', fragmentPath], { encoding: 'utf8', input: fs.readFileSync(path.join(HERE, 'fixtures', 'digitalocean.output.json'), 'utf8') });
    assert.equal(piped.status, 0, piped.stderr);
    assert.match(fs.readFileSync(fragmentPath, 'utf8'), /directPort: "25060"/);
  } finally {
    fs.rmSync(outside, { recursive: true, force: true });
  }
});

test('the test file itself sits in a work tree (positive control for the refusal)', () => {
  assert.equal(execFileSync('git', ['-C', HERE, 'rev-parse', '--is-inside-work-tree'], { encoding: 'utf8' }).trim(), 'true');
});
