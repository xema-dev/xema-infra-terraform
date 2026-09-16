#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
// BIND — the substrate's Terraform outputs, written into the two files the
// deployment root already reads. Node >= 20, ESM, zero dependencies.
//
//   terraform output -json \
//     | node tooling/bind/bind-outputs.mjs \
//         --secret-inputs <deployments/<d>/secret-inputs.fragment.yaml> \
//         --externals     <a path OUTSIDE any git work tree>
//
// WHAT IT IS
// ==========
// The third of the four internal phases — PROVISION / CONFIGURE-ALLOCATE /
// BIND / DEPLOY. PROVISION is `terraform apply`; DEPLOY is the deployment root
// (xema-deploy) applying charts. Between them sat a MANUAL step: read the stack
// outputs off `terraform output`, type the hosts into the committed
// `secret-inputs.yaml`, and type the credentials into the operator's externals
// file. This script is that step, made mechanical.
//
// It introduces NO contract. Both files it writes already exist in the
// deployment root's own shape:
//
//   secret-inputs.yaml   COMMITTED, credential-free: `<section>.<key>` scalars,
//                        the input surface `generate-deployment-secrets.mjs`
//                        renders `{{section.key}}` templates from.
//   externals            UNCOMMITTED: a flat `{ '<external name>': value }` map,
//                        one entry per `{{external:<name>}}` / OPERATOR_SUPPLIED
//                        credential in that generator's secret surface, passed
//                        with `--externals`.
//
// The ONE table below (`DISPOSITIONS`) says, per stack output, which of the two
// files a value goes to — or that it goes to neither, and why. The four
// dispositions are a closed set:
//
//   fragment   a non-secret fact → one `<section>.<key>` of the secret-inputs
//              fragment. REFUSED at runtime if the output is marked sensitive,
//              whatever the table says: the fragment is committed, and a
//              credential in it is the legacy plaintext tree coming back.
//   external   a credential → one entry of the externals file, under the NAME
//              the generator's surface reads. Nothing else may go there: an
//              entry under a name the generator does not read is a value with
//              no reader, and it would sit in a 0600 file looking bound.
//   operator   a credential an OPERATOR uses by hand (the admin database URI
//              that runs the database bootstrap, the kubeconfig) — read from
//              `terraform output -raw <name>` at that moment, NEVER written to
//              disk by this script. Named on stderr so the step is not
//              forgotten.
//   ignore     a fact neither file consumes today, with the reason. Named on
//              stderr so a reader can see it was classified, not dropped.
//
// An output the table does not know is REFUSED by name — a new stack output
// must be classified before this script will run over a document that carries
// it, because a silent drop is precisely the failure the manual step had. A
// `fragment` / `external` output that is null (its area disabled, consumed
// elsewhere, or not modelled on that cloud) is REFUSED naming the stack
// output, unless the table marks it `whenNull: omit` (an optional fact) or the
// operator declares the area consumed with `--consumed <output>`; either way
// the omission is printed.
//
// WHAT IT DELIBERATELY DOES NOT BIND — read this before "fixing" it
// ----------------------------------------------------------------
// The deployment root MINTS the Postgres role password itself
// (`shared-postgres-credentials.password` is a GENERATED key of its secret
// surface, not an external), and its database bootstrap script tells the
// operator to create the role WITH that minted password. The stack's
// `postgres_uri` is the ADMIN credential that bootstrap runs under; it is not
// the role password and no externals name receives it. So the join for the
// role password does not exist in either repository today, and this script
// refuses to invent one: `postgres_uri` is `operator`, printed with the command
// it is for. The Azure `postgres_role_passwords` are `operator` for the same
// reason — the role the stack created and the role the generator minted a
// password for are two authorities for one password until one of the two
// repositories yields. Likewise the Azure blob account: the deployment root's
// object-store surface is S3-shaped (`objectStore.endpoint`, a MinIO/S3
// endpoint); an Azure Blob endpoint under that key would be consumed as an S3
// endpoint, so `blob_*` are `ignore`, not `fragment`.
//
// USAGE
//   terraform output -json | node tooling/bind/bind-outputs.mjs --secret-inputs F --externals X
//   node tooling/bind/bind-outputs.mjs --from outputs.json --secret-inputs F --externals X \
//        [--identity-client <realm_clients key>] [--consumed <output>[,<output>]]
// ═══════════════════════════════════════════════════════════════════════════

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export class BindError extends Error {}

/** Where an output's value goes. Closed set. */
export const Disposition = Object.freeze({
  Fragment: 'fragment',
  External: 'external',
  Operator: 'operator',
  Ignore: 'ignore',
});

/** What a null `fragment` / `external` value means. Closed set. */
export const WhenNull = Object.freeze({
  Refuse: 'refuse',
  Omit: 'omit',
});

/** The realm_clients key of the identity-api client, unless --identity-client says otherwise. */
export const DEFAULT_IDENTITY_CLIENT = 'identity-api';

const f = (target, whenNull = WhenNull.Refuse, note = null) => ({ disposition: Disposition.Fragment, target, whenNull, note });
const x = (name, whenNull = WhenNull.Refuse, note = null) => ({ disposition: Disposition.External, name, whenNull, note });
const op = (reason) => ({ disposition: Disposition.Operator, reason });
const ign = (reason) => ({ disposition: Disposition.Ignore, reason });

/**
 * THE TABLE. One row per stack output, and per key of the `substrate` binding
 * map (`substrate.<key>`, the cross-cloud contract in docs/CONTRACTS.md). Both
 * stacks' outputs are here; a key one cloud always leaves null is `omit`.
 *
 * Top-level outputs that duplicate a `substrate.*` key are `ignore`d as
 * duplicates so the map is the one source read.
 */
export const DISPOSITIONS = Object.freeze({
  // ── the binding contract map ─────────────────────────────────────────────
  'substrate.postgres_host': f('postgres.directHost'),
  'substrate.postgres_port': f('postgres.directPort'),
  'substrate.postgres_app_role': f('postgres.role', WhenNull.Omit, 'DigitalOcean models no app role (postgres_roles is a flat input); declare postgres.role yourself'),
  'substrate.keycloak_url': f('keycloak.issuer', WhenNull.Refuse, 'joined with substrate.realm_name as <keycloak_url>/realms/<realm_name>'),
  'substrate.realm_name': f('keycloak.issuer', WhenNull.Refuse, 'joined with substrate.keycloak_url'),
  'substrate.redis_host': f('redis.host', WhenNull.Omit, 'no managed cache on this cloud, or enable_cache = false'),
  'substrate.redis_port': f('redis.port', WhenNull.Omit, 'no managed cache on this cloud, or enable_cache = false'),

  'substrate.deployment_name': ign('the deployment root has its own deployment.yaml#name; the stack does not decide it'),
  'substrate.environment': ign('no secret-inputs key reads an environment axis'),
  'substrate.region': ign('the cloud region is not a deployment input; objectStore.region is the object store\'s region, not the cloud\'s'),
  'substrate.tenant_id': ign('the External Secrets reader identity is bound by the ingress-tls addon, not by the deployment root'),
  'substrate.cluster_name': ign('the deployment root targets a kube-context, not a cluster name'),
  'substrate.cluster_resource_group_name': ign('an Azure placement fact; nothing in the deployment root reads it'),
  'substrate.oidc_issuer_url': ign('the cluster OIDC issuer feeds federated identities inside the stack, not the deployment root'),
  'substrate.storage_class_name': ign('a StorageClass name is a chart value (infra.yaml / values overlays), not a secret input'),
  'substrate.namespaces': ign('the namespace roster is the deployment root\'s own deployment.yaml; the stack only ensured it'),
  'substrate.postgres_provisioner_role': ign('the deployment root has no provisioner-role input; its pooler and app legs both use postgres.role'),
  'substrate.postgres_databases': ign('database NAMES are the deployment root\'s secret-inputs (postgres.*Database), derived from its own roster; the stack only ensured them'),
  'substrate.blob_account': ign('the deployment root\'s object-store surface is S3-shaped (objectStore.endpoint); an Azure Blob account has no key there'),
  'substrate.blob_endpoint': ign('the deployment root\'s object-store surface is S3-shaped (objectStore.endpoint); an Azure Blob endpoint is not an S3 endpoint'),
  'substrate.blob_container_prefix': ign('objectStore.blobContainerPrefix is derived by the deployment root from infra.yaml#minio.bucket; the Azure blob account is not bound (see blob_endpoint)'),
  'substrate.key_vault_name': ign('Key Vault is read by the ExternalSecrets ClusterSecretStore the ingress-tls addon installs, not by the deployment root'),
  'substrate.key_vault_uri': ign('same as key_vault_name'),
  'substrate.external_secrets_client_id': ign('same as key_vault_name'),
  'substrate.cluster_secret_store_name': ign('a manifest reference (ExternalSecret.secretStoreRef.name), not a secret input'),
  'substrate.dns_zone': ign('the deployment root derives hostnames from its own domain declarations (deployment-domains), not from a zone apex input'),
  'substrate.dns_name_servers': ign('a registrar delegation fact for the operator; the deployment root does not read it'),
  'substrate.ingress': ign('the ingress edge is a chart/values concern (ingress class, issuer annotation), not a secret input'),

  // ── top-level outputs ────────────────────────────────────────────────────
  cluster_id: ign('a provider id for imports'),
  cluster_endpoint: ign('the deployment root reaches the cluster through a kube-context; the endpoint travels inside kubeconfig_raw'),
  kubeconfig_raw: op('the kube-context the deployment root deploys through: `terraform output -raw kubeconfig_raw > ~/.kube/<deployment>.yaml` (chmod 600), then name that context in the deploy dispatch'),
  vpc_id: ign('a network id; nothing in the deployment root reads it'),
  oidc_issuer_url: ign('duplicate of substrate.oidc_issuer_url'),
  postgres_host: ign('duplicate of substrate.postgres_host'),
  postgres_port: ign('duplicate of substrate.postgres_port'),
  postgres_uri: op('the ADMIN credential the database bootstrap runs under: `psql "$(terraform output -raw postgres_uri)" -f deployments/<d>/bootstrap/postgres-databases.sql`. It is NOT the role password: the deployment root mints shared-postgres-credentials.password itself and its bootstrap says to create the role with THAT value — no externals name receives a Postgres credential today'),
  postgres_role_passwords: op('Azure: the passwords the stack gave the roles it created. The deployment root mints its own role password (shared-postgres-credentials, GENERATED) and no externals name receives one, so this and the minted value are two authorities for one password; reconcile by hand (ALTER ROLE … PASSWORD to the minted value) until one repository yields'),
  postgres_databases: ign('duplicate of substrate.postgres_databases'),
  postgres_roles: ign('the roles the stack ensured; the deployment root names its role in postgres.role'),
  dns_domain: ign('duplicate of substrate.dns_zone'),
  dns_name_servers: ign('duplicate of substrate.dns_name_servers'),
  dns_record_ids: ign('provider record ids for imports'),
  blob_account: ign('duplicate of substrate.blob_account'),
  blob_endpoint: ign('duplicate of substrate.blob_endpoint'),
  blob_primary_access_key: op('Azure: the blob account key. Not written: the deployment root\'s object-store surface is S3-shaped and its `object-store-secret-key` external pairs with an S3 access key (objectStore.accessKey), which an Azure account key is not. Bind it when that surface grows an Azure Blob shape'),
  key_vault_name: ign('duplicate of substrate.key_vault_name'),
  key_vault_uri: ign('duplicate of substrate.key_vault_uri'),
  redis_host: ign('duplicate of substrate.redis_host'),
  redis_port: ign('duplicate of substrate.redis_port'),
  redis_primary_key: x('redis-password', WhenNull.Omit, 'no managed cache on this cloud, or enable_cache = false'),
  storage_class_name: ign('duplicate of substrate.storage_class_name'),
  cluster_issuer_name: ign('a manifest annotation value (cert-manager.io/cluster-issuer), not a secret input'),
  cluster_secret_store_name: ign('duplicate of substrate.cluster_secret_store_name'),
  workload_namespaces: ign('duplicate of substrate.namespaces'),
  realm_id: ign('equal to the realm name; the issuer is derived from substrate.keycloak_url + substrate.realm_name'),
  realm_client_secrets: x('keycloak-identity-client-secret', WhenNull.Refuse, 'the entry keyed by --identity-client (default identity-api); a PUBLIC client has an empty secret and is refused'),
  extension_buckets: ign('extension-claimed buckets are the extension\'s own binding, keyed by an id the deployment root does not know'),
  extension_databases: ign('extension-claimed databases are the extension\'s own binding'),
});

// ── helpers ──────────────────────────────────────────────────────────────────

const isNil = (v) => v === null || v === undefined;

/** `{{secret-inputs}}` fragment: sections of `key: value`, values JSON-quoted (valid YAML). */
function toYamlFragment(sections) {
  const lines = [
    '# GENERATED by xema-infra-terraform tooling/bind/bind-outputs.mjs from `terraform output -json`.',
    '# Credential-free by construction: every value below came from a NON-sensitive stack output.',
    '# Merge into deployments/<d>/secret-inputs.yaml; an explicit key there wins over a derived one.',
  ];
  for (const [section, keys] of Object.entries(sections)) {
    lines.push(`${section}:`);
    for (const [key, value] of Object.entries(keys)) {
      lines.push(`  ${key}: ${JSON.stringify(String(value))}`);
    }
  }
  return `${lines.join('\n')}\n`;
}

/** Refuse a path inside a git work tree. `git` answering anything but a clean `false` refuses. */
export function assertOutsideWorkTree(p, runGit = execFileSync) {
  const dir = path.dirname(path.resolve(p));
  if (!fs.existsSync(dir)) throw new BindError(`--externals directory does not exist: ${dir}`);
  let out;
  try {
    out = String(runGit('git', ['-C', dir, 'rev-parse', '--is-inside-work-tree'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] })).trim();
  } catch (error) {
    // `git` exits 128 with "not a git repository" for a directory outside any
    // repository — that is the answer we want. Anything else (git missing,
    // permission denied) cannot prove the path is outside, so it refuses.
    const status = error?.status;
    const stderr = String(error?.stderr ?? '');
    if (status === 128 || /not a git repository/i.test(stderr)) return;
    throw new BindError(`cannot verify that ${p} is outside a git work tree: git failed (${error?.message ?? error}); refusing to write credentials there`);
  }
  if (out === 'true') {
    throw new BindError(`--externals ${p} is inside a git work tree. It holds cleartext credentials; keep it outside every repository so no commit can pick it up.`);
  }
  if (out !== 'false') {
    throw new BindError(`cannot verify that ${p} is outside a git work tree: git answered '${out}'; refusing to write credentials there`);
  }
}

/**
 * Bind a `terraform output -json` document. Pure: returns what would be
 * written plus the stderr report, throws BindError on any refusal.
 */
export function bind(doc, { identityClient = DEFAULT_IDENTITY_CLIENT, consumed = [] } = {}) {
  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    throw new BindError('expected the object `terraform output -json` prints (output name → { sensitive, type, value })');
  }
  const consumedSet = new Set(consumed);
  const report = { omitted: [], operator: [], ignored: [], written: [] };
  const fragment = {};
  const externals = {};

  // Flatten: top-level outputs, plus `substrate.<key>` for each key of the map.
  const entries = new Map();
  for (const [name, out] of Object.entries(doc)) {
    if (out === null || typeof out !== 'object' || !('value' in out)) {
      throw new BindError(`output '${name}' is not a terraform output entry ({ sensitive, type, value })`);
    }
    if (name === 'substrate') {
      if (out.sensitive) throw new BindError('output substrate is marked sensitive; the binding contract carries no credentials by definition — refusing');
      if (isNil(out.value)) throw new BindError('output substrate is null; the binding contract map must exist to bind');
      if (typeof out.value !== 'object' || Array.isArray(out.value)) throw new BindError('output substrate is not a map');
      for (const [key, value] of Object.entries(out.value)) entries.set(`substrate.${key}`, { sensitive: false, value });
    } else {
      entries.set(name, { sensitive: Boolean(out.sensitive), value: out.value });
    }
  }

  const unknown = [...entries.keys()].filter((k) => !(k in DISPOSITIONS));
  if (unknown.length > 0) {
    throw new BindError(`unknown stack output(s): ${unknown.join(', ')} — classify each in DISPOSITIONS (tooling/bind/bind-outputs.mjs) before binding; nothing is dropped silently`);
  }
  for (const c of consumedSet) {
    if (!(c in DISPOSITIONS)) throw new BindError(`--consumed names '${c}', which is not a stack output this table knows`);
  }

  // The fragment keys that REQUIRE an output; joined keys collect both halves.
  const joined = {};
  const setFragment = (target, value, from) => {
    const [section, key] = target.split('.');
    fragment[section] ??= {};
    fragment[section][key] = value;
    report.written.push(`${from} → secret-inputs ${target}`);
  };

  for (const [name, row] of Object.entries(DISPOSITIONS)) {
    const entry = entries.get(name);
    switch (row.disposition) {
      case Disposition.Ignore: {
        if (entry) report.ignored.push(`${name}: ${row.reason}`);
        break;
      }
      case Disposition.Operator: {
        if (entry && !isNil(entry.value)) report.operator.push(`${name}: ${row.reason}`);
        break;
      }
      case Disposition.Fragment: {
        if (!entry) {
          if (name.startsWith('substrate.')) throw new BindError(`the binding contract lacks '${name}' — this document was not produced by a stack of this module set (docs/CONTRACTS.md § Binding contract)`);
          throw new BindError(`required stack output '${name}' is absent from the document — add it to the consumer root's outputs`);
        }
        if (entry.sensitive) throw new BindError(`output '${name}' is marked sensitive but the table routes it to the committed secret-inputs fragment — refusing; fix the table or the output`);
        if (isNil(entry.value)) {
          if (row.whenNull === WhenNull.Omit || consumedSet.has(name)) {
            report.omitted.push(`${row.target} ← ${name} is null (${consumedSet.has(name) ? 'declared --consumed' : row.note})`);
            break;
          }
          throw new BindError(`stack output '${name}' is null, and secret-inputs ${row.target} needs it. Either the area is disabled/consumed elsewhere — then declare it with --consumed ${name} and supply ${row.target} yourself — or the apply has not happened yet`);
        }
        if (row.target === 'keycloak.issuer') {
          joined[name] = String(entry.value);
          break;
        }
        setFragment(row.target, entry.value, name);
        break;
      }
      case Disposition.External: {
        if (!entry) {
          // A cloud that does not model the area declares no such output at
          // all (DigitalOcean has no redis_primary_key); that is the null case
          // one step earlier, and only an optional row may take it.
          if (row.whenNull === WhenNull.Omit) {
            report.omitted.push(`external ${row.name} ← ${name} is absent from the document (${row.note})`);
            break;
          }
          throw new BindError(`required stack output '${name}' is absent from the document — add it to the consumer root's outputs (it is the source of external '${row.name}')`);
        }
        if (!entry.sensitive) throw new BindError(`output '${name}' is not marked sensitive but the table routes it to the externals file — refusing; a credential the stack does not mark sensitive is a defect in the stack`);
        let value = entry.value;
        if (name === 'realm_client_secrets' && !isNil(value)) {
          if (typeof value !== 'object' || Array.isArray(value)) throw new BindError('realm_client_secrets is not a map keyed by realm_clients key');
          if (!(identityClient in value)) {
            throw new BindError(`realm_client_secrets has keys [${Object.keys(value).join(', ')}]; none is '${identityClient}' — pass --identity-client <the realm_clients key of the identity-api client>`);
          }
          value = value[identityClient];
          if (typeof value !== 'string' || value === '') {
            throw new BindError(`realm_client_secrets['${identityClient}'] is empty — a PUBLIC client has no secret, and the identity-api client must be CONFIDENTIAL`);
          }
        }
        if (isNil(value)) {
          if (row.whenNull === WhenNull.Omit || consumedSet.has(name)) {
            report.omitted.push(`external ${row.name} ← ${name} is null (${consumedSet.has(name) ? 'declared --consumed' : row.note})`);
            break;
          }
          throw new BindError(`stack output '${name}' is null, and external '${row.name}' needs it — declare --consumed ${name} and supply it yourself, or apply first`);
        }
        externals[row.name] = value;
        report.written.push(`${name} → externals ${row.name}`);
        break;
      }
      default:
        throw new BindError(`table row '${name}' has unknown disposition '${row.disposition}'`);
    }
  }

  if (joined['substrate.keycloak_url'] && joined['substrate.realm_name']) {
    const url = joined['substrate.keycloak_url'].replace(/\/+$/, '');
    setFragment('keycloak.issuer', `${url}/realms/${joined['substrate.realm_name']}`, 'substrate.keycloak_url + substrate.realm_name');
  }

  return { fragment, externals, report };
}

// ── CLI ──────────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = { from: null, secretInputs: null, externals: null, identityClient: DEFAULT_IDENTITY_CLIENT, consumed: [] };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    const next = () => {
      const v = argv[++i];
      if (v === undefined) throw new BindError(`${a} needs a value`);
      return v;
    };
    if (a === '--from') out.from = next();
    else if (a === '--secret-inputs') out.secretInputs = next();
    else if (a === '--externals') out.externals = next();
    else if (a === '--identity-client') out.identityClient = next();
    else if (a === '--consumed') out.consumed.push(...next().split(',').map((s) => s.trim()).filter(Boolean));
    else throw new BindError(`unknown argument ${a}`);
  }
  if (!out.secretInputs && !out.externals) throw new BindError('nothing to write: pass --secret-inputs <path> and/or --externals <path>');
  return out;
}

function printReport(report) {
  const section = (title, lines) => {
    if (lines.length === 0) return;
    process.stderr.write(`${title}\n`);
    for (const l of lines) process.stderr.write(`  ${l}\n`);
  };
  section('written', report.written);
  section('omitted (null — supply yourself)', report.omitted);
  section('operator step (read with `terraform output -raw`, never written by this script)', report.operator);
  section('ignored (no consumer in the deployment root)', report.ignored);
}

export function main(argv = process.argv.slice(2)) {
  const args = parseArgs(argv);
  const raw = args.from ? fs.readFileSync(args.from, 'utf8') : fs.readFileSync(0, 'utf8');
  let doc;
  try {
    doc = JSON.parse(raw);
  } catch (error) {
    throw new BindError(`input is not the JSON that 'terraform output -json' prints: ${error.message}`);
  }
  if (args.externals) assertOutsideWorkTree(args.externals);
  const { fragment, externals, report } = bind(doc, { identityClient: args.identityClient, consumed: args.consumed });
  if (args.secretInputs) {
    fs.writeFileSync(args.secretInputs, toYamlFragment(fragment), 'utf8');
    process.stderr.write(`wrote ${args.secretInputs} (${Object.values(fragment).reduce((n, s) => n + Object.keys(s).length, 0)} key(s), no sensitive value)\n`);
  }
  if (args.externals) {
    // JSON is YAML; the generator loads the file with a YAML parser. 0600 on
    // create, and chmod afterwards for the case the file already existed.
    fs.writeFileSync(args.externals, `${JSON.stringify(externals, null, 2)}\n`, { encoding: 'utf8', mode: 0o600 });
    fs.chmodSync(args.externals, 0o600);
    process.stderr.write(`wrote ${args.externals} (${Object.keys(externals).length} credential(s), mode 0600)\n`);
  }
  printReport(report);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    if (error instanceof BindError) {
      process.stderr.write(`bind-outputs: ${error.message}\n`);
      process.exitCode = 1;
    } else {
      throw error;
    }
  }
}
