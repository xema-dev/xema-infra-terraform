// node --test tooling/check-assigned-roles.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';

import { check } from './check-assigned-roles.mjs';

const AGG = (entries) => `locals {\n  by_module = {\n${entries}\n  }\n}\n`;
const MOD = (role, list = role) =>
  ({ 'main.tf': `resource "azurerm_role_assignment" "x" {\n  role_definition_name = "${role}"\n}\n`,
     'outputs.tf': `output "assigned_role_names" {\n  value = ["${list}"]\n}\n` });

function tree(files) {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'assigned-roles-'));
  for (const [rel, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(tmp, rel)), { recursive: true });
    fs.writeFileSync(path.join(tmp, rel), text);
  }
  return tmp;
}
const run = (files) => { const t = tree(files); try { return check(t); } finally { fs.rmSync(t, { recursive: true, force: true }); } };
const mod = (name, m) => Object.fromEntries(Object.entries(m).map(([f, t]) => [`modules/providers/azure/${name}/${f}`, t]));

test('the live repository publishes every role', () => {
  assert.deepEqual(check(), []);
});

test('a consistent tree passes', () => {
  assert.deepEqual(run({ 'modules/assigned-roles/main.tf': AGG('    "a" = ["R1"]'), ...mod('a', MOD('R1')) }), []);
});

test('a role missing from the list fails', () => {
  const p = run({ 'modules/assigned-roles/main.tf': AGG('    "a" = ["R1"]'), ...mod('a', MOD('R2', 'R1')) });
  assert.ok(p.some((x) => /assigned_role_names output/.test(x)) && p.some((x) => /lists/.test(x)));
});

test('a module with no entry fails', () => {
  const p = run({ 'modules/assigned-roles/main.tf': AGG('    "b" = ["R1"]'), ...mod('a', MOD('R1')) });
  assert.ok(p.some((x) => /no "a" entry/.test(x)) && p.some((x) => /no module of that name/.test(x)));
});

test('a role named in a comment does not count; a non-literal name fails', () => {
  const files = { 'modules/assigned-roles/main.tf': AGG('    "a" = ["R1"]'), ...mod('a', MOD('R1')) };
  files['modules/providers/azure/a/extra.tf'] = '# role_definition_name = "Ghost"\nresource "azurerm_role_assignment" "y" {\n  role_definition_name = var.role\n}\n';
  const p = run(files);
  assert.equal(p.length, 1);
  assert.match(p[0], /plain string literal/);
});
