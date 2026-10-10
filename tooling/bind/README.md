# bind

`bind-outputs.mjs` writes a stack's Terraform outputs into the deployment root's two input files: the committed, credential-free `secret-inputs.yaml` (endpoints) and an operator-held externals file kept outside every repository (credentials).

Node 20 or later, ESM, no dependencies. It only reads the JSON that `output -json` prints, which is identical from OpenTofu and Terraform. It runs no `init`, `plan` or `apply`.

## When to use it

Use it after `apply`, so nobody types endpoints or credentials by hand.

## Usage

```sh
terraform output -json \
  | node tooling/bind/bind-outputs.mjs \
      --secret-inputs <deployment root>/deployments/<d>/secret-inputs.yaml \
      --externals    "$HOME/.config/acme/externals.json"

# or from a saved document
node tooling/bind/bind-outputs.mjs --from outputs.json --secret-inputs ... --externals ...
```

`--secret-inputs` merges into the committed file: derived keys that are missing are added, everything else is preserved, and a key you declared with a different value is kept and reported. A file whose shape the merge cannot read is refused and left untouched.

Run the deployment root's generator afterwards with `--externals` pointing at the externals file.

## Configuration

| Option | Meaning |
| --- | --- |
| `--from <file>` | read outputs from a file instead of stdin |
| `--secret-inputs <file>` | the `secret-inputs.yaml` to merge endpoints into |
| `--externals <file>` | the operator externals file to write credentials into |
| `--identity-client <key>` | the `realm_clients` key of the identity-api client (default `identity-api`) |
| `--deployment <name>` | selects the entry of the per-deployment custody maps (default: the stack's `deployment_name`) |
| `--consumed <output>[,...]` | a null output is an area consumed elsewhere, so its key is omitted instead of refused |

The report on stderr lists what was written, omitted and ignored, and which credentials are operator steps.

## Mapping

| Stack output | Goes to | Key |
| --- | --- | --- |
| `substrate.postgres_host`, `postgres_port` | secret-inputs | `postgres.directHost`, `postgres.directPort` |
| `substrate.postgres_app_role` | secret-inputs | `postgres.role` |
| `substrate.keycloak_url` and `realm_name` | secret-inputs | `keycloak.issuer` (`<url>/realms/<realm>`) |
| `substrate.redis_host`, `redis_port` | secret-inputs | `redis.host`, `redis.port` |
| `realm_client_secrets[--identity-client]` | externals | `keycloak-identity-client-secret` |
| `redis_primary_key` | externals | `redis-password` |
| `custody_vault_urls`, `custody_broker_client_ids` | secret-inputs | `credentialCustody.vaultUrl`, `credentialCustody.brokerClientId` |
| `postgres_uri`, `kubeconfig_raw`, `blob_primary_access_key`, `substrate.gateway` | never written | operator steps |
| `postgres_role_passwords` | ignored | role passwords are reconciled from the deployment's sealed secret |

Every other stack output is ignored with a reason. An output the table does not know is refused by name, and a sensitive output is refused if it would land in the committed file. A root declares its own extra outputs as not-a-binding with an `xema_bind_root_local_outputs` output (a list of output names).

## Tests

```sh
node --test 'tooling/bind/*.test.mjs'
```
