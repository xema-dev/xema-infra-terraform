# Changelog

Consumers pin this module set by `?ref=vX.Y.Z`. Every entry below names what a
consumer root on the PREVIOUS tag must change to adopt the release — not what
was committed, but what a `main.tf` + tfvars have to say differently.

## UNRELEASED — `cluster-addons/deployer-identity`

**The RBAC bootstrap stops being a hand step.** A deployment's namespaces, the
least-privileged ServiceAccount its pipeline deploys as, that account's token
and the cluster-identity facts a deploy verifies before it writes are now a
module, applied by the same run that creates the cluster. What used to be
`kubectl apply -f bootstrap/00-namespaces-and-deployer-rbac.yaml` with a
cluster-admin kubeconfig on somebody's laptop — once per deployment, re-applied
from a runbook whenever a grant changed — is a flag and one declared namespace.

### To adopt

Nothing changes for a consumer that does not opt in: `enable_deployer_identity`
defaults to **false**, so `init -upgrade` on this version creates no
ServiceAccount and no token.

```hcl
enable_deployer_identity       = true
deployer_namespace             = "acme-prod"          # what the deployment DECLARES
deployer_additional_namespaces = ["acme-prod-infra"]  # no implicit suffix is derived
# DigitalOcean stack only — it names every resource explicitly rather than
# deriving them from one deployment name:
deployer_deployment_name       = "acme-prod"
```

Then, once per deployment:

```sh
tofu output -raw deployer_kubeconfig   # or: terraform output -raw
```

### New outputs

| output | |
| --- | --- |
| `deployer_kubeconfig` | sensitive; the value a deployment's `kubeconfigRef` names. Null when the area is disabled |
| `substrate.cluster_identity` | non-secret: `server`, `ca_certificate_sha256` (sha256 of the DECODED CA), `kube_system_namespace_uid` |

`cluster_identity` carries no context name on purpose. A context name is a local
kubeconfig ALIAS — the same cluster is `owl-k8s` in one operator's file and
`default` in another's — so a consumer comparing aliases refuses a correct
cluster and admits a wrong one that happens to share the name. The three facts
above cannot be satisfied by a rename.

### Adopting an existing hand-applied bootstrap

Every object is importable, so a cluster bootstrapped by hand moves under
Terraform with no re-apply and no downtime; `manage_namespaces = false` leaves
namespace ownership wherever it already is. Import ids are in the module README.

## v0.6.1 — 2026-09-16 (tag `v0.6.1` = `7735dac`, cut from `develop` like `v0.6.0`; promotion to `main` is PR #1)

**`tooling/bind/bind-outputs.mjs --secret-inputs` MERGES.** Aimed at the
committed `deployments/<d>/secret-inputs.yaml` — the file every procedure
names — v0.6.0 REPLACED it with the derived fragment: measured on the first
customer, 55 hand-written lines became 12. It now adds the derived keys the
file lacks (at the end of their section; a missing section is appended),
preserves every byte the owner wrote, and KEEPS a key the owner declared with
a different value than the stack's, reporting the disagreement (`merged: KEPT
— …`) instead of absorbing it. A prior fragment of its own (first line = the
generated banner) or an absent file is still written whole; a file whose
shape the merge cannot read (a nested mapping or list inside a section the
stack writes) is refused by line and left untouched. Nothing a consumer root's
`main.tf` or tfvars say changes. Pinned by three new cases in
`tooling/bind/bind-outputs.test.mjs`.

## v0.6.0 — UNRELEASED (tagged by the coordinator after promotion)

**Breaking: the stacks stop knowing the application.** Two inputs that used to
default to one deployment's roster are REQUIRED with no default; a stack
invoked without them refuses to plan. The substrate is capability-shaped —
Kubernetes, Postgres, DNS, a realm — and which databases and namespaces exist
is the consumer's fact, derived from what it deploys.

### Breaking inputs

| where | change |
| --- | --- |
| `stacks/digitalocean/xema-substrate` | `postgres_databases` → **`platform_databases`** (renamed, now REQUIRED, `set(string)`, verbatim; `[]` when `enable_managed_postgres = false`) |
| `stacks/digitalocean/xema-substrate` | **`workload_namespaces`** now REQUIRED (`set(string)`, DNS-1123 labels); its seven-namespace default is deleted |
| `modules/cluster-addons/workload-namespaces` | **`namespaces`** now REQUIRED; its default is deleted |
| `modules/cluster-addons/shared-templates-volume` | inputs **renamed**: `orchestrator_namespace` → `owner_namespace`, `orchestrator_pvc_name` → `owner_pvc_name`, `workers_namespace` + `workers_pvc_name` → `consumer_mounts` (`map(namespace => claim)`); `name_prefix` REQUIRED; resource addresses are now `owner` and `consumer[<ns>]` (`terraform state mv` or re-import); the `shared_templates_pool_slug` output is deleted. This module is UNTAGGED — it landed on `main` after v0.5.0 and its only consumers pin it by SHA, which is what this row is for |
| `modules/providers/cloudflare/edge` | **`websocket_paths`** REQUIRED (`set(string)`, each starting with `/`; `[]` declares none); a plan turning `websockets_enabled` off while paths are declared is refused. Also untagged-since-v0.5.0, consumed by SHA |

### Added

- **`stacks/azure/xema-substrate`** — the second full substrate: AKS,
  Flexible Server, Azure DNS, a blob account, plus three optional primitives
  the DigitalOcean stack lacks (`secrets-backend` = Key Vault + External
  Secrets identity, `cache` = Azure Cache for Redis, and the cloud-agnostic
  **`cluster-addons/ingress-tls`** addon: ingress-nginx, cert-manager +
  `ClusterIssuer`, External Secrets + `ClusterSecretStore`). One
  `deployment_name` derives every name. `platform_databases` and
  `workload_namespaces` are REQUIRED there too.
- **The `substrate` output** on BOTH stacks — the binding contract, one map of
  non-secret facts with the same keys on every cloud (`docs/CONTRACTS.md §
  Binding contract`). The DigitalOcean stack also gains `postgres_databases`.
- **`realm_access_token_lifespan`** (both stacks, `identity-realm`) —
  optional, default `""` (inherits Keycloak's 5m). Set it so the lifespan is
  intent.
- **Engine policy as data.** OpenTofu is the default execution engine and
  HashiCorp Terraform is supported on customer mandate; the modules are one
  standard-HCL set for both. `terraform-portable` is every module's unrecorded
  default; the exception is `locals { xema_engine_profile = "opentofu-native" }`
  in a module's `versions.tf`. `tooling/check-engine-profile.mjs` fails an
  undeclared module that uses an OpenTofu-only construct, naming it; CI
  validates every module on both engines (`docs/CONTRACTS.md § Engine and
  authoring profile`). The first two-engine run fixed
  `providers/azure/cluster`'s `endpoint` output (derived from the sensitive
  `kube_config`; now `nonsensitive()`, which both engines accept).
- **`tooling/bind/bind-outputs.mjs`** — BIND made mechanical: `tofu output
  -json` or `terraform
  output -json` → the deployment root's `secret-inputs.yaml` fragment
  (endpoints) and its operator externals file (credentials, 0600, refused
  inside any git work tree). One explicit table; an unknown output is
  refused by name. `tooling/bind/README.md`.
- **`examples/customer/`** — the minimal customer-owned consumer root:
  module version + tfvars, never a forked stack.
- `docs/CONTRACTS.md` — the capability matrix (EXISTING | MANAGED | NOT
  REQUIRED per capability, and which module provides MANAGED) and the three
  ownership modes with the mode 2→3 handoff as an ordered list of bindings.

### Migrating a consumer root from `?ref=v0.5.0`

Derived from `git diff v0.5.0 v0.6.0 -- stacks/digitalocean/xema-substrate/variables.tf`.
In the root's tfvars (or `-var`):

1. **Rename `postgres_databases` to `platform_databases`.** Same type and
   meaning. If your root passed nothing (it took the default `[]`), you must
   now pass it explicitly: the databases you deploy, or `[]` when
   `enable_managed_postgres = false`.
2. **Pass `workload_namespaces` explicitly.** If your root relied on the
   default, the seven names it used to get were `xema-prod`, `shared-prod`,
   `xema-infra`, `xema-opencode-workers`, `xema-biome-sidecars`,
   `xema-biome-apis`, `xema-image-builders` — pass the roster YOU run
   (`kubectl get ns` on the live cluster is the honest source), so the plan
   is `0 to add, 0 to change, 0 to destroy`.
3. Optionally set **`realm_access_token_lifespan`** (e.g. `"5m"`). A root that
   already passed it against a pin that lacked it — the known consumer does —
   stops erroring on an unsupported argument.
4. If your `main.tf` passes each input through explicitly (the
   `examples/digitalocean` shape), rename the argument in the module block
   too: `postgres_databases = …` → `platform_databases = …`.
5. Read the `substrate` output instead of individual facts where you bind a
   consumer; the individual outputs are unchanged and still there.
6. Roots consuming `shared-templates-volume` or `cloudflare/edge` by SHA:
   apply the rename row above (`state mv` for the volume module's addresses)
   and declare `websocket_paths`.

Then `terraform plan` on the existing deployment MUST report **0 to add, 0 to
change, 0 to destroy** before you apply.

## v0.5.0 — 2026-06-22

- `identity-realm`: ignore operator-owned realm configuration (adopt, don't
  strip).

## v0.4.0 and earlier

See the git tags; no changelog was kept before v0.6.0.
