// node tooling/check-assigned-roles.mjs
//
// Makes a missing role impossible by construction. modules/assigned-roles lists, per module, the
// Azure role definition names that module assigns; a bootstrap derives its ABAC allow-list from it.
// This check fails when:
//   - a `role_definition_name` anywhere under modules/ or stacks/ is not a string literal, or a
//     `role_definition_id` is used (the name cannot be read, so it cannot be listed);
//   - a module that assigns a role has no entry in modules/assigned-roles (keyed by its directory
//     name), or its entry differs from the names in its code;
//   - the module's own `assigned_role_names` output differs from the names in its code;
//   - an entry in modules/assigned-roles names no module that assigns roles.
// Self-contained (node builtins only), like the other checks in this directory.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const stripComments = (text) =>
  text.split('\n').filter((l) => !/^\s*(#|\/\/)/.test(l)).map((l) => l.replace(/\s+#\s.*$/, '')).join('\n');

function* tfFiles(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.name === '.terraform' || e.name === 'node_modules') continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* tfFiles(p);
    else if (e.name.endsWith('.tf')) yield p;
  }
}

const literals = (s) => [...s.matchAll(/"([^"]*)"/g)].map((m) => m[1]);
const sameSet = (a, b) => JSON.stringify([...new Set(a)].sort()) === JSON.stringify([...new Set(b)].sort());

export function check(root = ROOT) {
  const problems = [];
  const used = new Map(); // module dir (relative) -> Set of names
  for (const top of ['modules', 'stacks']) {
    if (!fs.existsSync(path.join(root, top))) continue;
    for (const file of tfFiles(path.join(root, top))) {
      const rel = path.relative(root, file);
      const text = stripComments(fs.readFileSync(file, 'utf8'));
      if (/\brole_definition_id\s*=/.test(text)) problems.push(`${rel}: role_definition_id cannot be listed; use a literal role_definition_name`);
      for (const m of text.matchAll(/\brole_definition_name\s*=\s*(.+)/g)) {
        const lit = m[1].trim().match(/^"([^"$]*)"$/);
        if (!lit) { problems.push(`${rel}: role_definition_name must be a plain string literal, got ${m[1].trim()}`); continue; }
        const dir = path.relative(root, path.dirname(file));
        if (!used.has(dir)) used.set(dir, new Set());
        used.get(dir).add(lit[1]);
      }
    }
  }

  const aggFile = path.join(root, 'modules/assigned-roles/main.tf');
  const agg = new Map();
  if (!fs.existsSync(aggFile)) { problems.push('modules/assigned-roles/main.tf is missing'); return problems; }
  const aggText = stripComments(fs.readFileSync(aggFile, 'utf8'));
  const block = aggText.match(/by_module\s*=\s*\{([\s\S]*?)\n\s*\}/);
  if (!block) problems.push('modules/assigned-roles/main.tf: no by_module map');
  else for (const m of block[1].matchAll(/"([^"]+)"\s*=\s*\[([^\]]*)\]/g)) agg.set(m[1], literals(m[2]));

  for (const [dir, names] of used) {
    const key = path.basename(dir);
    const code = [...names];
    if (!agg.has(key)) problems.push(`${dir}: assigns ${JSON.stringify(code)} but modules/assigned-roles has no "${key}" entry`);
    else if (!sameSet(agg.get(key), code)) problems.push(`${dir}: code assigns ${JSON.stringify(code.sort())} but modules/assigned-roles lists ${JSON.stringify(agg.get(key))}`);
    const out = path.join(root, dir, 'outputs.tf');
    const outText = fs.existsSync(out) ? stripComments(fs.readFileSync(out, 'utf8')) : '';
    const o = outText.match(/output\s+"assigned_role_names"\s*\{[\s\S]*?value\s*=\s*\[([^\]]*)\]/);
    if (!o) problems.push(`${dir}: no static assigned_role_names output (a literal list)`);
    else if (!sameSet(literals(o[1]), code)) problems.push(`${dir}: assigned_role_names output ${JSON.stringify(literals(o[1]))} differs from the code ${JSON.stringify(code.sort())}`);
  }
  for (const key of agg.keys()) {
    if (![...used.keys()].some((d) => path.basename(d) === key)) problems.push(`modules/assigned-roles lists "${key}" but no module of that name assigns a role`);
  }
  return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const problems = check();
  if (problems.length) { console.error(problems.join('\n')); process.exit(1); }
  console.log('assigned role names: every role_definition_name in modules/ and stacks/ is published. OK.');
}
