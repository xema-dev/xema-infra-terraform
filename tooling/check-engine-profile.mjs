#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
// The ENGINE PROFILE of every module and stack, and the one check that makes
// it data.
//
// Owner policy (2026-09-16): OpenTofu is the default execution ENGINE;
// HashiCorp Terraform is supported when a customer mandates it. The engine is
// not the definition — one module set, standard HCL, never a tofu/terraform
// fork, and no wrapper, DSL, registry or manifest of any kind.
//
// THE CONVENTION, decided by the coordinator and recorded here once:
//
//   terraform-portable   the zero-configuration DEFAULT. Recorded NOWHERE — a
//                        module says nothing and is portable.
//   opentofu-native      the EXCEPTION, declared in the module's versions.tf
//                        beside its required_version:
//
//                            locals { xema_engine_profile = "opentofu-native" }
//
//                        A module that uses an OpenTofu-only construct on
//                        purpose declares this and does not advertise
//                        portability.
//
// What makes the default data rather than a hope is THIS check: per leaf, an
// OpenTofu-only construct present WITHOUT that local fails, naming the
// construct, the file and the line. Detection is a closed, named list; each
// row is a construct HashiCorp Terraform's language does not accept (the
// repository pins `required_version >= 1.6`, so the Terraform 1.7+ `removed`
// block counts as non-portable too, at the floor the modules declare). What
// the list cannot see it does not claim to — the stronger proof is CI running
// `terraform validate` for every portable leaf.
//
//   node tooling/check-engine-profile.mjs                 # grade modules/ and stacks/
//   node tooling/check-engine-profile.mjs --list native   # print the opentofu-native leaves (CI skips them on the terraform leg)
//   node --test tooling/check-engine-profile.test.mjs     # the mutation cases
// ═══════════════════════════════════════════════════════════════════════════
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LABEL = '[check-engine-profile]';

/** Closed set. */
export const Profile = Object.freeze({
  TerraformPortable: 'terraform-portable',
  OpenTofuNative: 'opentofu-native',
});

/** The one declaration: `locals { xema_engine_profile = "opentofu-native" }` in versions.tf. */
const NATIVE_LOCAL = /^\s*xema_engine_profile\s*=\s*"opentofu-native"\s*$/m;
/** Any other value under that name is a typo we refuse rather than read as portable. */
const ANY_PROFILE_LOCAL = /^\s*xema_engine_profile\s*=\s*"([^"]*)"\s*$/m;

/**
 * OpenTofu-only constructs this check detects, as anchored patterns over
 * COMMENT-STRIPPED HCL. Named, so a refusal says which construct and where.
 */
export const TOFU_ONLY = Object.freeze([
  { name: 'a .tofu source file', file: /\.tofu$/, pattern: null },
  { name: 'state encryption: terraform { encryption { … } }', file: /\.tf$/, pattern: /^\s*encryption\s*\{/m },
  { name: 'a removed { … } block (not in Terraform at the >= 1.6 floor the modules declare)', file: /\.tf$/, pattern: /^\s*removed\s*\{/m },
  { name: 'terraform.applying', file: /\.tf$/, pattern: /\bterraform\.applying\b/ },
  { name: 'a provider-defined function call (provider::…)', file: /\.tf$/, pattern: /\bprovider::[a-z0-9_]+::[a-z0-9_]+\s*\(/ },
  { name: 'provider iteration (for_each on a provider block)', file: /\.tf$/, pattern: /^provider\s+"[^"]+"\s*\{[^}]*?^\s*for_each\s*=/ms },
  { name: 'an engine-naming required_version (tofu/opentofu)', file: /\.tf$/, pattern: /required_version\s*=\s*"[^"]*(tofu|opentofu)[^"]*"/i },
]);

/** HCL comments blanked in place (line numbers preserved): hash, double-slash and block comments. Strings and heredocs are respected. */
export function stripHclComments(src) {
  let out = '';
  let i = 0;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    const c2 = src.slice(i, i + 2);
    if (c === '"') {
      let j = i + 1;
      while (j < n && src[j] !== '"') { if (src[j] === '\\') j += 1; j += 1; }
      // Kept verbatim: two declarations this check reads live INSIDE a
      // string (the profile local, required_version). Every construct
      // pattern is line-anchored or keyword-shaped, so a construct quoted in
      // an ordinary string does not match; a heredoc (below) is blanked.
      out += src.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    if (c2 === '<<') {
      const m = /^<<-?([A-Z_][A-Z0-9_]*)\r?\n/.exec(src.slice(i));
      if (m) {
        const end = new RegExp(`^\\s*${m[1]}\\s*$`, 'm');
        const rest = src.slice(i + m[0].length);
        const e = end.exec(rest);
        const stop = e ? i + m[0].length + e.index + e[0].length : n;
        // A heredoc is a string: blank its body so a construct QUOTED in one
        // (the state-bucket modules print a backend block as a hint) is never
        // read as a construct USED.
        out += src.slice(i, stop).replace(/[^\n]/g, ' ');
        i = stop;
        continue;
      }
    }
    if (c === '#' || c2 === '//') {
      while (i < n && src[i] !== '\n') { out += ' '; i += 1; }
      continue;
    }
    if (c2 === '/*') {
      const end = src.indexOf('*/', i + 2);
      const stop = end === -1 ? n : end + 2;
      out += src.slice(i, stop).replace(/[^\n]/g, ' ');
      i = stop;
      continue;
    }
    out += c;
    i += 1;
  }
  return out;
}

export function leaves(root) {
  const out = new Set();
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const p = path.join(dir, e.name);
      if (e.isDirectory()) { if (e.name !== '.terraform') walk(p); }
      else if (/\.(tf|tofu)$/.test(e.name)) out.add(dir);
    }
  };
  for (const top of ['modules', 'stacks']) if (fs.existsSync(path.join(root, top))) walk(path.join(root, top));
  return [...out].sort();
}

/** Grade one leaf: { leaf, profile, evidence[], findings[] }. */
export function gradeLeaf(root, leaf) {
  const rel = path.relative(root, leaf);
  const findings = [];
  let profile = Profile.TerraformPortable;
  const versions = path.join(leaf, 'versions.tf');
  if (fs.existsSync(versions)) {
    const body = stripHclComments(fs.readFileSync(versions, 'utf8'));
    const any = ANY_PROFILE_LOCAL.exec(body);
    if (any && !NATIVE_LOCAL.test(body)) {
      findings.push(`${rel}/versions.tf: xema_engine_profile = "${any[1]}" is not a profile; the only declaration is "opentofu-native" (terraform-portable is the unrecorded default)`);
    } else if (any) {
      profile = Profile.OpenTofuNative;
    }
  }
  // The declaration lives in versions.tf and nowhere else: a local elsewhere
  // would be a second place to look, so it is refused rather than honoured.
  for (const e of fs.readdirSync(leaf)) {
    if (e === 'versions.tf' || !/\.tf$/.test(e)) continue;
    const body = stripHclComments(fs.readFileSync(path.join(leaf, e), 'utf8'));
    if (ANY_PROFILE_LOCAL.test(body)) findings.push(`${rel}/${e}: xema_engine_profile is declared outside versions.tf — it lives beside required_version, nowhere else`);
  }
  const evidence = [];
  let filesScanned = 0;
  for (const e of fs.readdirSync(leaf)) {
    const p = path.join(leaf, e);
    if (!fs.statSync(p).isFile() || !/\.(tf|tofu)$/.test(e)) continue;
    filesScanned += 1;
    for (const rule of TOFU_ONLY) {
      if (!rule.file.test(e)) continue;
      if (rule.pattern === null) { evidence.push(`${rel}/${e}: ${rule.name}`); continue; }
      const body = stripHclComments(fs.readFileSync(p, 'utf8'));
      const hit = rule.pattern.exec(body);
      if (hit) evidence.push(`${rel}/${e}:${body.slice(0, hit.index).split('\n').length}: ${rule.name}`);
    }
  }
  if (profile === Profile.TerraformPortable && evidence.length > 0) {
    findings.push(...evidence.map((ev) => `${ev} — an OpenTofu-only construct in a leaf that declares no profile (= terraform-portable). Declare locals { xema_engine_profile = "opentofu-native" } in its versions.tf, or remove the construct`));
  }
  return { leaf: rel, profile, evidence, findings, filesScanned };
}

export function grade(root = ROOT) {
  const all = leaves(root);
  const graded = all.map((l) => gradeLeaf(root, l));
  return { graded, findings: graded.flatMap((g) => g.findings) };
}

export function run(root = ROOT, { list = null } = {}) {
  const { graded, findings } = grade(root);
  if (graded.length === 0) {
    console.error(`${LABEL} FAIL: no leaf with *.tf under modules/ or stacks/ — an empty scan is not coverage`);
    return 1;
  }
  if (list === 'native') {
    for (const g of graded) if (g.profile === Profile.OpenTofuNative) console.log(g.leaf);
    return findings.length > 0 ? 1 : 0;
  }
  const native = graded.filter((g) => g.profile === Profile.OpenTofuNative).length;
  const files = graded.reduce((n, g) => n + g.filesScanned, 0);
  // The corpus is printed beside the verdict so a layout change that moves
  // modules out from under modules/ or stacks/ reads as a shrinking number,
  // never as a clean tree.
  console.log(`${LABEL} modules scanned: ${graded.length}, files scanned: ${files} — ${graded.length - native} terraform-portable (default, undeclared), ${native} opentofu-native (declared); ${TOFU_ONLY.length} OpenTofu-only construct(s) detectable`);
  if (files === 0) {
    console.error(`${LABEL} FAIL: zero .tf files scanned — an empty corpus is not coverage`);
    return 1;
  }
  for (const g of graded) console.log(`  ${g.profile}  ${g.leaf}${g.evidence.length ? `  (tofu-only: ${g.evidence.length})` : ''}`);
  if (findings.length > 0) {
    console.error(`${LABEL} FAIL: ${findings.length} finding(s)`);
    for (const f of findings) console.error(`  ${f}`);
    return 1;
  }
  console.log(`${LABEL} OK — no undeclared leaf uses a detectable OpenTofu-only construct.`);
  return 0;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const li = process.argv.indexOf('--list');
  process.exitCode = run(ROOT, { list: li === -1 ? null : process.argv[li + 1] });
}
