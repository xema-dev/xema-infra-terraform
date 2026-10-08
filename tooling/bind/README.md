# BIND — stack outputs into the deployment root's two input files

`terraform apply` (PROVISION) ends with facts and credentials in Terraform
state. The deployment root (the Helm GitOps consumer, `xema-deploy`) reads
neither the state nor `terraform output`: it consumes ENDPOINTS from its
committed, credential-free `deployments/<d>/secret-inputs.yaml`, and
CREDENTIALS from an operator file kept OUTSIDE every repository and passed
to its secret generator as `--externals <file>`. Getting the outputs into
those two files was a manual step. `bind-outputs.mjs` is that step.

Node ≥ 20, ESM, zero dependencies. **It consumes bindings and never drives
the engine.** Its only input is the JSON that `output -json` prints, and that
document is byte-identical from OpenTofu and from HashiCorp Terraform — so the
script neither knows nor cares which engine produced the state, runs no
`init`/`plan`/`apply`, and is not a wrapper, a DSL or a state layer of any
kind. Two commands, in either spelling:

```sh
# from the consumer root, after apply — OpenTofu (the default engine) …
tofu output -json \
  | node <xema-infra-terraform>/tooling/bind/bind-outputs.mjs \
      --secret-inputs <deployment root>/deployments/<d>/secret-inputs.yaml \
      --externals    "$HOME/.config/acme/externals.json"
# … or HashiCorp Terraform, when the customer mandates it: same script, same flags
terraform output -json \
  | node <xema-infra-terraform>/tooling/bind/bind-outputs.mjs \
      --secret-inputs <deployment root>/deployments/<d>/secret-inputs.yaml \
      --externals    "$HOME/.config/acme/externals.json"

# or from a saved document
tofu output -json > /somewhere/outside/outputs.json        # or: terraform output -json
node <xema-infra-terraform>/tooling/bind/bind-outputs.mjs --from /somewhere/outside/outputs.json \
     --secret-inputs <deployment root>/deployments/<d>/secret-inputs.yaml --externals "$HOME/.config/acme/externals.json"
```

**`--secret-inputs` MERGES into the committed `secret-inputs.yaml`** (v0.6.1):
a derived key the file lacks is added at the end of its section (a missing
section is appended), every byte the owner wrote — keys, comments, order —
is preserved, and a key the owner declared with a DIFFERENT value than the
stack's is KEPT and reported (`merged: KEPT — …`): an explicit key wins over
a derived one, and the disagreement is printed rather than absorbed. Until
v0.6.1 the script wrote a FRAGMENT and REPLACED whatever file the path named
— aimed at the committed file, 55 hand-written lines became 12 — so the only
safe target was a separate `secret-inputs.fragment.yaml` merged by hand.
That still works: a file that is a prior fragment of the script's own (its
first line is the generated banner), or absent, is written whole. A file
whose shape the merge cannot read — a nested mapping or a list inside a
section the stack writes into — is refused naming the line and left
untouched; add those keys by hand. Then run the deployment root's generator
with `--externals` pointing at the externals file.

Options: `--identity-client <realm_clients key>` names which realm client is
the identity-api client (default `identity-api`); `--consumed <output>[,…]`
declares that a null output is an area consumed elsewhere (`enable_* = false`)
so its key is omitted rather than refused. The report on stderr lists what was
written, what was omitted and why, which credentials are OPERATOR steps read
with `terraform output -raw`, and which outputs nothing consumes.

## The mapping — the whole of it

The table is `DISPOSITIONS` in the script; this is its content. `substrate.*`
is the cross-cloud binding map (`docs/CONTRACTS.md § Binding contract`);
top-level outputs that duplicate a map key are ignored as duplicates.

| stack output | goes to | key | when null |
| --- | --- | --- | --- |
| `substrate.postgres_host` | secret-inputs | `postgres.directHost` | refused (or `--consumed`) |
| `substrate.postgres_port` | secret-inputs | `postgres.directPort` | refused (or `--consumed`) |
| `substrate.postgres_app_role` | secret-inputs | `postgres.role` | omitted — DigitalOcean models no app role |
| `substrate.keycloak_url` + `substrate.realm_name` | secret-inputs | `keycloak.issuer` = `<url>/realms/<realm>` | refused (or `--consumed`) |
| `substrate.redis_host` / `redis_port` | secret-inputs | `redis.host` / `redis.port` | omitted — no managed cache |
| `realm_client_secrets[--identity-client]` | externals | `keycloak-identity-client-secret` | refused; a PUBLIC client (empty secret) is refused |
| `redis_primary_key` (Azure) | externals | `redis-password` | omitted — absent or null on a cloud without a managed cache |
| `custody_vault_urls[<deployment>]` / `custody_broker_client_ids[<deployment>]` | secret-inputs | `credentialCustody.vaultUrl` / `credentialCustody.brokerClientId` — the entry for `--deployment <name>` (default: the stack's `deployment_name` output); a deployment absent from the map is SKIPPED (omitted loudly; e.g. a shared root with no custody); a non-map, a sensitive output or a malformed entry is refused | omitted — custody not provisioned |
| `deployment_name` | **ignored** | not a binding: it keys the per-deployment maps above and defaults `--deployment` | — |
| `postgres_uri` | **operator** — never written | the ADMIN credential the deployment root's database bootstrap runs under: `psql "$(terraform output -raw postgres_uri)" -f deployments/<d>/bootstrap/postgres-databases.sql` | — |
| `kubeconfig_raw` | **operator** — never written | the kube-context the deployment root deploys through | — |
| `substrate.gateway` (Azure) | **operator** — never written | `deployments/<d>/values.yaml#gateway.parentRef` `{ name, namespace, sectionName }`: a nested mapping the two-level merge cannot write — print it with the `jq` on stderr and paste it once | — |
| `postgres_role_passwords` (Azure) | **ignored**, with a reason on stderr | see below — role passwords are declared and reconciled, not bound | — |
| `blob_primary_access_key` (Azure) | **operator** — never written | see below | — |
| everything else (`cluster_id`, `vpc_id`, `dns_*`, `storage_class_name`, `workload_namespaces`, `postgres_databases`, `realm_id`, `extension_*`, `operator_vault_*`, `gateway_parent_ref`, `cluster_issuer_name`, `secret_store_name`/`secret_stores`, `blob_account`/`blob_endpoint`, and every other `substrate.*` key) | **ignored**, each with a reason on stderr | nothing in the two files consumes it | — |

Two properties are enforced at runtime, not only by the table: an output the
table does not know is REFUSED by name (nothing is dropped silently), and an
output marked `sensitive` is refused if the table would put it in the
committed fragment.

## What is deliberately NOT bound, and why — read before "fixing"

- **The Postgres role password.** It is DECLARED, not bound, and there is
  exactly one authority for it: the deployment's own sealed secret surface. The
  deployment root mints `shared-postgres-credentials.password` (a GENERATED key,
  not an external), and a scripted path reconciles Postgres to it —
  `xema-deploy`'s `scripts/apply-postgres-bootstrap.sh` for the deployment-wide
  `postgres.role`, and its `provision-service-database-roles` workflow for the
  per-service `<svc>_migrator` / `<svc>_runtime` pairs a
  `ServiceDatabaseRoleContract` declares. Both read the sealed Secret and run
  `ALTER ROLE … PASSWORD`; the Secret is the desired state and Postgres is
  reconciled to it.

  So Azure's `postgres_role_passwords` are IGNORED. They are whatever the stack
  set when it created the roles, they are superseded by the next reconcile, and
  copying them anywhere would create a second value for a fact that already has
  one.

  **This used to say the operator reconciled the two by hand with
  `ALTER ROLE <app role> PASSWORD '<the minted value>'`, and that path is
  removed.** A duplicate authority for a credential is bad in a way worth
  naming: the hand path leaves no receipt, so a divergence between the two
  surfaces as an authentication failure at some later deploy rather than as a
  conflict at the moment it is created. `postgres_uri` remains `operator` —
  that one is the ADMIN credential the database bootstrap runs under, which is
  a different fact and genuinely has no home in either file.

  This tool still refuses to invent a missing externals key; a value under a
  name nothing reads is a credential sitting in a file looking bound.
- **Azure Blob.** The deployment root's object-store surface is S3-shaped
  (`objectStore.endpoint`, `objectStore.accessKey`, external
  `object-store-secret-key`). An Azure Blob endpoint under that key would be
  consumed as an S3 endpoint, and the account key is not an S3 secret key. The
  `blob_*` outputs are classified and left, until that surface grows an Azure
  shape.
- **`postgres.directParams`.** Not an output. Both managed offerings require
  TLS; declare `sslmode=require` yourself.

## Tests

```sh
node --test 'tooling/bind/*.test.mjs'
```

Fixtures under `fixtures/` are one `terraform output -json` document per stack
carrying every output that stack declares; a stack output added without a table
row reddens the suite.
