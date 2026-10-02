// node --test tooling/check-engine-profile.test.mjs
//
// Mutation cases in a throwaway tree, plus the live corpus. The one that
// matters most is the comment-standing case: a construct named only in prose
// must not fire, because every module's docs explain what they avoid.

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { Profile, TOFU_ONLY, grade, gradeLeaf } from './check-engine-profile.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PORTABLE_VERSIONS = 'terraform {\n  required_version = ">= 1.6"\n}\n';
const NATIVE_VERSIONS = 'terraform {\n  required_version = ">= 1.6"\n}\n\nlocals {\n  xema_engine_profile = "opentofu-native"\n}\n';

function tree(files) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'engine-profile-'));
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(tmp, rel)), { recursive: true });
    fs.writeFileSync(path.join(tmp, rel), text);
  }
  return tmp;
}
const leaf = (files, name = 'modules/m') => {
  const tmp = tree(files);
  try { return gradeLeaf(tmp, path.join(tmp, name)); } finally { fs.rmSync(tmp, { recursive: true, force: true }); }
};

test('a leaf that declares nothing is terraform-portable and clean', () => {
  const g = leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': 'resource "null_resource" "x" {}\n' });
  assert.equal(g.profile, Profile.TerraformPortable);
  assert.deepEqual(g.findings, []);
});

test('a leaf with no versions.tf at all is still portable by default (the default is recorded nowhere)', () => {
  const g = leaf({ 'modules/m/main.tf': 'resource "null_resource" "x" {}\n' });
  assert.equal(g.profile, Profile.TerraformPortable);
  assert.deepEqual(g.findings, []);
});

for (const [name, body] of [
  ['state encryption', 'terraform {\n  encryption {\n    method "aes_gcm" "m" {}\n  }\n}\n'],
  ['a removed block', 'removed {\n  from = null_resource.x\n}\n'],
  ['terraform.applying', 'output "o" { value = terraform.applying }\n'],
  ['a provider-defined function', 'output "o" { value = provider::corefunc::str_snake("x") }\n'],
  ['provider for_each', 'provider "aws" {\n  for_each = var.regions\n  region   = each.value\n}\n'],
  ['an engine-naming required_version', 'terraform {\n  required_version = ">= 1.8, opentofu"\n}\n'],
]) {
  test(`${name} in an undeclared leaf is refused, naming the construct`, () => {
    const g = leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': body });
    assert.equal(g.findings.length, 1, JSON.stringify(g));
    assert.match(g.findings[0], /modules\/m\/main\.tf:\d+: /);
    assert.match(g.findings[0], /opentofu-native/);
  });
  test(`${name} in a leaf declaring opentofu-native is accepted`, () => {
    const g = leaf({ 'modules/m/versions.tf': NATIVE_VERSIONS, 'modules/m/main.tf': body });
    assert.equal(g.profile, Profile.OpenTofuNative);
    assert.deepEqual(g.findings, []);
    assert.equal(g.evidence.length, 1);
  });
}

test('a .tofu file in an undeclared leaf is refused', () => {
  const g = leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tofu': 'resource "null_resource" "x" {}\n' });
  assert.equal(g.findings.length, 1);
  assert.match(g.findings[0], /\.tofu source file/);
});

test('THE comment-standing case: a construct named only in comments does not fire', () => {
  const prose = '# we deliberately avoid encryption {\n// and removed {\n/* and provider::x::y(  and terraform.applying */\nresource "null_resource" "x" {}\n';
  const g = leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': prose });
  assert.deepEqual(g.findings, []);
  assert.deepEqual(g.evidence, []);
  // …and the same text as CODE fires (two-sided control).
  const code = 'terraform {\n  encryption {\n  }\n}\n';
  assert.equal(leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': code }).evidence.length, 1);
});

test('a construct inside a heredoc or a string does not fire', () => {
  const body = 'output "hint" {\n  value = <<-EOT\n    terraform {\n      encryption {\n      }\n    }\n  EOT\n}\noutput "s" { value = "removed {" }\n';
  assert.deepEqual(leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': body }).evidence, []);
});

test('a profile local with any other value is refused, and one outside versions.tf is refused', () => {
  const typo = leaf({ 'modules/m/versions.tf': 'locals {\n  xema_engine_profile = "terraform-portable"\n}\n' });
  assert.equal(typo.findings.length, 1);
  assert.match(typo.findings[0], /is not a profile/);
  const elsewhere = leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': 'locals {\n  xema_engine_profile = "opentofu-native"\n}\n' });
  assert.equal(elsewhere.findings.length, 1);
  assert.match(elsewhere.findings[0], /outside versions\.tf/);
});

test('the live corpus: every leaf under modules/ and stacks/ is terraform-portable with no finding', () => {
  const { graded, findings } = grade(ROOT);
  assert.ok(graded.length >= 21, `expected >= 21 leaves, got ${graded.length}`);
  assert.deepEqual(findings, []);
  assert.deepEqual(graded.filter((g) => g.profile !== Profile.TerraformPortable), []);
  assert.ok(TOFU_ONLY.length >= 7);
});

test('a dynamic block with for_each INSIDE a provider is plain Terraform, not provider iteration', () => {
  const body = 'provider "kubernetes" {\n  host = "h"\n  dynamic "exec" {\n    for_each = var.on ? [1] : []\n    content {\n      command = "kubelogin"\n    }\n  }\n}\n';
  const g = leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': body });
  assert.deepEqual(g.findings, []);
});

test('a top-level provider for_each after ordinary attributes is still refused', () => {
  const body = 'provider "aws" {\n  region   = "x"\n  for_each = var.regions\n}\n';
  const g = leaf({ 'modules/m/versions.tf': PORTABLE_VERSIONS, 'modules/m/main.tf': body });
  assert.equal(g.findings.length, 1, JSON.stringify(g));
});
