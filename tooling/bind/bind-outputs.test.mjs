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

import { BindError, DISPOSITIONS, ROOT_LOCAL_OUTPUT, Disposition, assertOutsideWorkTree, bind, mergeIntoSecretInputs } from './bind-outputs.mjs';

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
  // Role passwords are declared in the deployment's sealed secret surface and
  // reconciled into Postgres by a scripted path, so the stack's values are not
  // an authority and are IGNORED. This asserted `operator` while a hand-run
  // ALTER ROLE reconciled two competing sources; that path is removed.
  assert.ok(report.ignored.some((l) => l.startsWith('postgres_role_passwords:')));
  assert.ok(!report.operator.some((l) => l.startsWith('postgres_role_passwords:')));
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
  assert.throws(() => bind(doc), /partial identity-realm data.*realm_client_secrets/);
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

// ── THE BINDER TRAP (v0.6.1) ────────────────────────────────────────────────
// Aimed at the committed deployments/<d>/secret-inputs.yaml — the file every
// procedure names — --secret-inputs REPLACED it with the derived fragment (a
// 55-line hand file became 12 lines on the first customer). It MERGES now.

/** The shape a committed secret-inputs.yaml has: comments, blank lines, owner keys, sections the stack knows nothing about. */
const COMMITTED = `# secret-inputs for acme-prod — hand-authored; endpoints only, never a credential.
postgres:
  # the role the platform's databases are created for
  role: acme_prod_app
  directHost: pg.acme.internal      # the operator's alias; the stack disagrees
  directParams: sslmode=require

keycloak:
  issuer: "https://id.acme.example/realms/acme-prod"

llm:
  openaiBaseUrl: https://llm.acme.example/v1
  embeddingModel: Qwen/Qwen3-Embedding-8B
biomeFetcher:
  trustedOidcIssuer: https://token.actions.githubusercontent.com
  trustedPublishers: ''
`;

test('merge: every existing byte survives; missing derived keys are added in their section; a differing owner key is KEPT and reported; an equal one is `same`', () => {
  const { fragment } = bind(fixture('azure'));
  const { text, report } = mergeIntoSecretInputs(COMMITTED, fragment);
  // Nothing the owner wrote is lost — every original line is still there, in order.
  const original = COMMITTED.split('\n').filter((l) => l !== '');
  let cursor = 0;
  for (const line of text.split('\n')) if (line === original[cursor]) cursor += 1;
  assert.equal(cursor, original.length, `an original line was lost or reordered:\n${text}`);
  // Added: the keys the file lacked, appended at the END of their sections.
  assert.match(text, /^  directParams: sslmode=require\n  directPort: "5432"\n/m, 'directPort was not appended at the end of postgres:');
  assert.match(text, /^\nredis:\n  host: "acme-prod-redis\.redis\.cache\.windows\.net"\n  port: "6380"\n$/m, 'the redis section was not appended at the end of the file');
  assert.deepEqual(report.added.sort(), ['postgres.directPort', 'redis.host', 'redis.port']);
  // Kept: the owner's directHost differs from the stack's — the explicit key wins, loudly.
  assert.equal(report.kept.length, 1);
  assert.match(report.kept[0], /^postgres\.directHost: the file declares "pg\.acme\.internal", the stack says "acme-prod-pg\.postgres\.database\.azure\.com" — the explicit key wins/);
  assert.match(text, /^  directHost: pg\.acme\.internal      # the operator's alias; the stack disagrees$/m);
  // Same: role and issuer are already declared with the stack's value (quoted or not).
  assert.deepEqual(report.same.sort(), ['keycloak.issuer', 'postgres.role']);
  // Idempotent: merging the result again changes nothing.
  const again = mergeIntoSecretInputs(text, fragment);
  assert.equal(again.text, text);
  assert.deepEqual(again.report.added, []);
});

test('merge: a target section this merge cannot read (a nested mapping) is REFUSED by line, and the file is not touched', () => {
  const { fragment } = bind(fixture('azure'));
  const nested = 'postgres:\n  role: r\n  pooler:\n    host: x\n';
  assert.throws(() => mergeIntoSecretInputs(nested, fragment), /cannot merge into section 'postgres'.*line\(s\) 3, 4 are not/);
  assert.throws(() => mergeIntoSecretInputs('just a scalar\n', fragment), /not a section header/);
  // A section the fragment does NOT write into may hold anything.
  const elsewhere = 'llm:\n  models:\n    - a\n    - b\npostgres:\n  role: acme_prod_app\n';
  const { text } = mergeIntoSecretInputs(elsewhere, fragment);
  assert.match(text, /^llm:\n  models:\n    - a\n    - b\n/m);
});

test('CLI: aimed at a committed secret-inputs.yaml, --secret-inputs MERGES (55 lines stay 55+); a prior fragment of its own is rewritten whole', () => {
  const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'bind-merge-'));
  try {
    const committed = path.join(outside, 'secret-inputs.yaml');
    fs.writeFileSync(committed, COMMITTED);
    const before = COMMITTED.split('\n').length;
    const run = spawnSync(process.execPath, [SCRIPT, '--from', path.join(HERE, 'fixtures', 'azure.output.json'), '--secret-inputs', committed], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    const after = fs.readFileSync(committed, 'utf8');
    assert.ok(after.split('\n').length > before, `the file shrank: ${before} → ${after.split('\n').length}`);
    assert.ok(after.startsWith('# secret-inputs for acme-prod'), 'the owner\'s header was replaced');
    assert.match(run.stderr, /merged into .*secret-inputs\.yaml: 3 key\(s\) added, 2 already equal, 1 kept as declared/);
    assert.match(run.stderr, /KEPT — the file declares a different value/);

    // A prior fragment of the script's own is regenerated whole, as before.
    const fragmentPath = path.join(outside, 'fragment.yaml');
    spawnSync(process.execPath, [SCRIPT, '--from', path.join(HERE, 'fixtures', 'digitalocean.output.json'), '--secret-inputs', fragmentPath], { encoding: 'utf8' });
    const rerun = spawnSync(process.execPath, [SCRIPT, '--from', path.join(HERE, 'fixtures', 'azure.output.json'), '--secret-inputs', fragmentPath], { encoding: 'utf8' });
    assert.equal(rerun.status, 0, rerun.stderr);
    assert.match(rerun.stderr, /^wrote /m);
    assert.match(fs.readFileSync(fragmentPath, 'utf8'), /directPort: "5432"/);
    assert.doesNotMatch(fs.readFileSync(fragmentPath, 'utf8'), /25060/);

    // An unreadable target is refused and left byte-identical.
    const opaque = path.join(outside, 'opaque.yaml');
    fs.writeFileSync(opaque, 'postgres:\n  role: r\n  pooler:\n    host: x\n');
    const refused = spawnSync(process.execPath, [SCRIPT, '--from', path.join(HERE, 'fixtures', 'azure.output.json'), '--secret-inputs', opaque], { encoding: 'utf8' });
    assert.equal(refused.status, 1);
    assert.match(refused.stderr, /cannot merge into section 'postgres'/);
    assert.equal(fs.readFileSync(opaque, 'utf8'), 'postgres:\n  role: r\n  pooler:\n    host: x\n');
  } finally {
    fs.rmSync(outside, { recursive: true, force: true });
  }
});

// ── the deployer identity ────────────────────────────────────────────────────
//
// Both outputs are OPERATOR steps, and the test that matters is the negative
// one: a ServiceAccount kubeconfig is a credential, so it must reach NEITHER
// file this script writes. The positive half — that a document carrying them
// is classified rather than refused — is the regression guard for the table's
// own `unknown stack output(s)` throw, which fires on any output nobody
// classified and would otherwise break every consumer the day the stack grows
// the area.
for (const cloud of ['digitalocean', 'azure']) {
  test(`${cloud}: the deployer kubeconfig is an operator step and reaches neither file`, () => {
    const doc = fixture(cloud);
    const { fragment, externals, report } = bind(doc);

    assert.ok(
      report.operator.some((line) => line.startsWith('deployer_kubeconfig:')),
      'deployer_kubeconfig is reported as an operator step',
    );
    const written = JSON.stringify(fragment) + JSON.stringify(externals);
    assert.ok(!written.includes('FIXTURE-DEPLOYER-TOKEN'), 'the deployer token reached a written file');
    assert.ok(!written.includes('kind: Config'), 'a kubeconfig reached a written file');
  });

  test(`${cloud}: cluster identity is an operator step — three facts, no context alias`, () => {
    const doc = fixture(cloud);
    const identity = doc.substrate.value.cluster_identity;
    assert.deepEqual(
      Object.keys(identity).sort(),
      ['ca_certificate_sha256', 'kube_system_namespace_uid', 'server'],
      'the identity is exactly the three facts a rename cannot satisfy',
    );
    assert.ok(
      !Object.keys(identity).some((key) => /context/.test(key)),
      'a context name is an alias and must not be part of the identity',
    );
    assert.match(identity.ca_certificate_sha256, /^[a-f0-9]{64}$/);

    const { fragment, report } = bind(doc);
    assert.ok(
      report.operator.some((line) => line.startsWith('substrate.cluster_identity:')),
      'substrate.cluster_identity is reported as an operator step',
    );
    assert.equal(fragment.clusterIdentity, undefined, 'the identity is not a secret input');
  });

  test(`${cloud}: the gateway parentRef is an operator step, never a secret input`, () => {
    const doc = fixture(cloud);
    const { fragment, report } = bind(doc);
    assert.equal(fragment.gateway, undefined, 'the parentRef is not a secret input');
    const reported = report.operator.some((line) => line.startsWith('substrate.gateway:'));
    if (cloud === 'azure') {
      assert.deepEqual(Object.keys(doc.substrate.value.gateway.parent_ref).sort(), ['name', 'namespace', 'section_name']);
      assert.ok(reported, 'substrate.gateway is reported as an operator step');
    } else {
      assert.ok(!reported, 'a null gateway has nothing to report');
    }
  });
}

// ── per-deployment credential custody ───────────────────────────────────────

const withCustody = (extra = {}) => ({
  ...fixture('azure'),
  deployment_name: { sensitive: false, type: 'string', value: 'acme-prod' },
  custody_vault_urls: { sensitive: false, type: ['map', 'string'], value: { 'acme-prod': 'https://vault.acme.example', other: 'https://other.example' } },
  custody_broker_client_ids: { sensitive: false, type: ['map', 'string'], value: { 'acme-prod': 'client-1', other: 'client-2' } },
  ...extra,
});

test('custody: the deployment_name entry of each map binds to credentialCustody; deployment_name itself is ignored', () => {
  const { fragment, report } = bind(withCustody());
  assert.deepEqual(fragment.credentialCustody, { vaultUrl: 'https://vault.acme.example', brokerClientId: 'client-1' });
  assert.ok(report.ignored.some((l) => l.startsWith('deployment_name:')));
});

test('custody: --deployment overrides; a non-map is refused', () => {
  assert.equal(bind(withCustody(), { deployment: 'other' }).fragment.credentialCustody.brokerClientId, 'client-2');
  assert.throws(() => bind(withCustody({ custody_vault_urls: { sensitive: false, value: 'x' } })), /not a map/);
  const noName = withCustody();
  delete noName.deployment_name;
  noName.substrate = { ...noName.substrate, value: { ...noName.substrate.value, deployment_name: null } };
  assert.throws(() => bind(noName), /pass --deployment/);
});

test('custody: absent or null maps are omitted loudly; a sensitive one is refused', () => {
  const { fragment, report } = bind(withCustody({ custody_vault_urls: { sensitive: false, value: null } }));
  assert.equal(fragment.credentialCustody.vaultUrl, undefined);
  assert.ok(report.omitted.some((l) => l.startsWith('credentialCustody.vaultUrl')));
  assert.ok(bind(fixture('azure')).report.omitted.some((l) => l.startsWith('credentialCustody.brokerClientId')));
  assert.throws(() => bind(withCustody({ custody_vault_urls: { sensitive: true, value: { 'acme-prod': 'u' } } })), /marked sensitive/);
});

test('custody: a deployment absent from a per-deployment map is skipped with the omitted notice', () => {
  const { fragment, report } = bind(withCustody(), { deployment: 'aura-shared' });
  assert.equal(fragment.credentialCustody, undefined);
  assert.ok(report.omitted.some((l) => l.startsWith('credentialCustody.vaultUrl') && l.includes("no entry for deployment 'aura-shared'")));
  assert.ok(report.omitted.some((l) => l.startsWith('credentialCustody.brokerClientId') && l.includes("no entry for deployment 'aura-shared'")));
});

test('custody: a present entry is emitted; one map may skip while the other emits', () => {
  const doc = withCustody({ custody_broker_client_ids: { sensitive: false, type: ['map', 'string'], value: { other: 'client-2' } } });
  const { fragment, report } = bind(doc);
  assert.deepEqual(fragment.credentialCustody, { vaultUrl: 'https://vault.acme.example' });
  assert.ok(report.omitted.some((l) => l.startsWith('credentialCustody.brokerClientId')));
});

test('custody: a present but malformed entry is still refused', () => {
  assert.throws(() => bind(withCustody({ custody_vault_urls: { sensitive: false, value: { 'acme-prod': '' } } })), /not a non-empty string/);
  assert.throws(() => bind(withCustody({ custody_vault_urls: { sensitive: false, value: { 'acme-prod': 7 } } })), /not a non-empty string/);
  assert.throws(() => bind(withCustody({ custody_broker_client_ids: { sensitive: false, value: ['acme-prod'] } })), /not a map/);
});

// ── deployment without an in-platform IdP realm (external OIDC IdP) ─────────
const noRealm = () => {
  const doc = fixture('azure');
  doc.substrate.value.keycloak_url = null;
  doc.substrate.value.realm_name = null;
  doc.realm_client_secrets.value = null;
  return doc;
};

test('idp: realm present → issuer and identity client secret are emitted', () => {
  const { fragment, externals } = bind(fixture('azure'));
  assert.equal(fragment.keycloak.issuer, 'https://id.acme.example/realms/acme-prod');
  assert.equal(externals['keycloak-identity-client-secret'], 'FIXTURE-IDENTITY-CLIENT-SECRET');
});

test('idp: no realm at all → keycloak rows omitted loudly, not refused', () => {
  const { fragment, externals, report } = bind(noRealm());
  assert.equal(fragment.keycloak, undefined);
  assert.equal(externals['keycloak-identity-client-secret'], undefined);
  assert.ok(report.omitted.some((l) => l.startsWith('keycloak.issuer ← substrate.keycloak_url') && l.includes('external OIDC identity provider')));
  assert.ok(report.omitted.some((l) => l.startsWith('keycloak.issuer ← substrate.realm_name')));
  assert.ok(report.omitted.some((l) => l.startsWith('external keycloak-identity-client-secret ← realm_client_secrets')));
});

test('idp: partial realm data is refused (url without secrets, and secrets without url)', () => {
  const a = noRealm();
  a.substrate.value.keycloak_url = 'https://id.acme.example';
  a.substrate.value.realm_name = 'acme-prod';
  assert.throws(() => bind(a), (e) => e instanceof BindError && /partial identity-realm data/.test(e.message));
  const b = noRealm();
  b.realm_client_secrets.value = { 'identity-api': 'S' };
  assert.throws(() => bind(b), (e) => e instanceof BindError && /partial identity-realm data/.test(e.message));
});

test('idp: --identity-client for a deployment without a realm is refused', () => {
  assert.throws(() => bind(noRealm(), { identityClient: 'identity-api' }), (e) => e instanceof BindError && /contradictory/.test(e.message));
});

// ── every stack output field is classified (fails HERE, not in a consumer) ───
//
// Reads each stack's outputs.tf: every top-level `output "x"` and every key of
// the `substrate` object must have a DISPOSITIONS row.
const REPO = path.resolve(HERE, '..', '..');
for (const stack of ['azure', 'digitalocean']) {
  test(`${stack}: every stack output and every substrate field has a disposition`, () => {
    const src = fs.readFileSync(path.join(REPO, 'stacks', stack, 'xema-substrate', 'outputs.tf'), 'utf8');
    const top = [...src.matchAll(/^output "([a-z0-9_]+)"/gm)].map((m) => m[1]);
    assert.ok(top.includes('substrate'), 'outputs.tf declares the substrate output');
    const block = src.slice(src.indexOf('output "substrate"'));
    const body = block.slice(block.indexOf('value = {') + 'value = {'.length);
    const keys = [];
    for (const line of body.split('\n')) {
      if (/^  \}/.test(line)) break; // end of the value object
      const m = /^    ([a-z0-9_]+)\s+=/.exec(line);
      if (m) keys.push(m[1]);
    }
    assert.ok(keys.length > 10, `parsed the substrate keys (${keys.length})`);
    const missing = [...top.filter((n) => n !== 'substrate'), ...keys.map((k) => `substrate.${k}`)].filter((n) => !(n in DISPOSITIONS));
    assert.deepEqual(missing, [], `classify in DISPOSITIONS: ${missing.join(', ')}`);
  });
}

test('azure: kubelet identity and container registry fields are classified as not-a-binding', () => {
  for (const n of ['kubelet_identity_object_id', 'container_registry_login_server', 'container_registry_id']) {
    assert.equal(DISPOSITIONS[`substrate.${n}`].disposition, Disposition.Ignore);
    assert.equal(DISPOSITIONS[n].disposition, Disposition.Ignore);
  }
  const { report } = bind(fixture('azure'));
  assert.ok(report.ignored.some((l) => l.startsWith('substrate.container_registry_id:')));
});

// ── root-local outputs ───────────────────────────────────────────────────────

const withRootLocal = (names, extra = {}) => {
  const doc = fixture('azure');
  doc.temporal_workflow_attester = { sensitive: false, type: 'string', value: 'x' };
  doc[ROOT_LOCAL_OUTPUT] = { sensitive: false, type: ['list', 'string'], value: names };
  return Object.assign(doc, extra);
};

test('a root output is refused unless the root declares it root-local', () => {
  const doc = fixture('azure');
  doc.temporal_workflow_attester = { sensitive: false, type: 'string', value: 'x' };
  assert.throws(() => bind(doc), /unknown stack output\(s\): temporal_workflow_attester/);
});

test('a declared root-local output binds and is reported ignored; the declaration itself is not an unknown', () => {
  const { report, fragment } = bind(withRootLocal(['temporal_workflow_attester']));
  assert.ok(report.ignored.some((l) => l.startsWith('temporal_workflow_attester:')));
  assert.deepEqual(fragment, bind(fixture('azure')).fragment);
});

test('an undeclared output is still refused beside declared ones', () => {
  const doc = withRootLocal(['temporal_workflow_attester'], { other_thing: { sensitive: false, type: 'string', value: 'y' } });
  assert.throws(() => bind(doc), /unknown stack output\(s\): other_thing/);
});

test('a root-local name colliding with a stack output is refused', () => {
  assert.throws(() => bind(withRootLocal(['postgres_host'])), /stack output name/);
  assert.throws(() => bind(withRootLocal(['substrate'])), /stack output name/);
});

test('a root-local name that is not an output of the root, a duplicate, itself, or a bad shape is refused', () => {
  assert.throws(() => bind(withRootLocal(['nope'])), /not an output of this root/);
  assert.throws(() => bind(withRootLocal(['temporal_workflow_attester', 'temporal_workflow_attester'])), /twice/);
  assert.throws(() => bind(withRootLocal([ROOT_LOCAL_OUTPUT])), /cannot list itself/);
  assert.throws(() => bind(withRootLocal('temporal_workflow_attester')), /list of non-empty/);
  const doc = withRootLocal(['temporal_workflow_attester']);
  doc[ROOT_LOCAL_OUTPUT].sensitive = true;
  assert.throws(() => bind(doc), /sensitive/);
});
