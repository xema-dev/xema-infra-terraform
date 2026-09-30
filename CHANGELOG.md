# Changelog

Consumers pin this module set by `?ref=vX.Y.Z`. Every entry below names what a
consumer root on the PREVIOUS tag must change to adopt the release — not what
was committed, but what a `main.tf` + tfvars have to say differently.

## Unreleased — Azure modules can live inside an existing landing zone

No consumer change: every new input defaults to the previous behaviour. Proven by
planning the same greenfield root (network, cluster, Postgres, management runner)
over the previous and the new modules: 24 resources (a private endpoint included), identical attributes; the only
address that moves is the runner's public IP (`azurerm_public_ip.this` ->
`this[0]`), carried by a `moved` block.

What a root composing the primitives inside an enterprise landing zone (a network,
routing and DNS owned by someone else) can now say:

- `providers/azure/cluster`
  - `outbound_type` — AKS's own egress setting. `userDefinedRouting` creates no
    AKS egress; the node subnet's existing route (e.g. `0.0.0.0/0` to a firewall)
    decides. Requires `route_table_id`, on which the cluster identity is granted
    Network Contributor — a permission, never ownership of the route table.
  - `private_cluster_enabled` / `private_cluster_public_fqdn_enabled` — API only on
    a private address; optionally published under a public DNS name so resolvers
    that cannot see Azure private zones (a VNet on custom DNS) still reach it.
  - `entra_rbac` — Microsoft Entra ID authentication with Azure RBAC, local
    (certificate) accounts off by default when set.
- `providers/azure/managed-postgres` — `private_dns_zone_id`: consume an existing
  private DNS zone instead of creating and linking one.
- `providers/azure/managed-postgres` — `network_access = "private_endpoint"`: no
  public access and no VNet injection, reached through a private endpoint in a
  subnet that needs no delegation (a customer-owned subnet stays untouched).
- `providers/azure/private-endpoint` — service `postgres` (`postgresqlServer`), and
  `register_dns_record` (default true): false leaves the endpoint's A record to the
  network's owner, e.g. a landing zone that registers private endpoints in its
  central zones by policy. `providers/azure/network` accepts `postgres` in
  `private_link_services` (`privatelink.postgres.database.azure.com`).
- `providers/azure/management-runner` — `public_ip_enabled` (default true) and an
  optional `allowed_ssh_cidrs`: a private-only VM on a network whose default route
  goes to a firewall, where a public IP would answer asymmetrically.

Every primitive already accepted an existing `resource_group_name`.

- `providers/azure/state-bucket` — `shared_access_key_enabled` (default true): false
  leaves Entra ID as the only way to the state (backends set `use_azuread_auth`).
- Role assignments to the modules' own managed identities (cluster network and route
  table, the key-vault reader, the DNS-01 identity) declare `principal_type =
  "ServicePrincipal"`, so a deployer whose role-assignment right is limited to
  service principals (an ABAC condition) can make them.
- **Behaviour change:** `providers/azure/secrets-backend` grants the Terraform
  principal Key Vault Secrets Officer only when there are secrets to seed
  (`secret_names` non-empty) — the purpose its own description states; its
  propagation wait was already gated that way. A root seeding nothing no longer
  leaves a standing data-plane role behind.
- `stacks/azure/xema-substrate` passes all of it through, each input defaulting to
  today's behaviour (the stack's cloud phase planned before and after: 38
  resources, identical attributes):
  - `resource_group_name` — ONE existing resource group for everything the stack
    creates (a landing zone that grants a deployment exactly one);
  - `cluster_outbound_type`, `cluster_private` (`public_fqdn`), `cluster_entra_rbac`,
    `cluster_address_ranges` (service/DNS/pod ranges — on a landing zone they must
    avoid the corporate address plan; the module defaults sit in `10.100.0.0/16`);
  - `network.route_table_id` (optional) — the route table `userDefinedRouting` uses;
  - `postgres_network_access = "private_endpoint"` — the stack composes the
    server's private endpoint beside the others, in `network.private_dns_zone_ids["postgres"]`.
  - With `cluster_entra_rbac.local_account_disabled`, the stack's kubernetes/helm
    providers authenticate through `kubelogin` with the caller's Azure CLI identity;
    kubelogin must be on PATH where the stack runs.

## v0.7.1 — bind fixtures use the reserved placeholder shape

No consumer change: `tooling/bind/fixtures/*.json` only. The recorded
`kube_system_namespace_uid` sample was `11111111-2222-3333-4444-555555555555`,
the one GUID in these fixtures outside their own placeholder convention
(`xxxxxxxx-0000-4000-8000-xxxxxxxxxxxx`, used by every other id beside it). A
consumer that vendors this tree and sweeps it for committed identifiers cannot
tell that value from a real one; it is now `11111111-0000-4000-8000-555555555555`.
`bind-outputs.test.mjs`: 20/20.

## v0.7.0 — the first RELEASE with artifacts

v0.7.0 carries the two sections below (`azure-private-foundation` and
`postgres-tenancy`), and it is the first tag published as a release: the whole
tree as a deterministic archive, `MANIFEST.sha256` (every file's sha256) and
`SHA256SUMS` (`tooling/release/build-release.sh`, run by
`.github/workflows/release.yml` on every `v*` tag).

**How a consumer should take a release from now on:** pin the MANIFEST's digest
as the release's identity (it is the same wherever the release is rebuilt) and
the published archive's digest to verify its download, in its own lock, keep the artifacts in storage it controls
(its own registry, its own storage, or unpacked in its own repository), and
verify an unpacked tree with `sha256sum -c MANIFEST.sha256`. A deployment
consuming a release that way plans and applies without this repository, this
organisation or GitHub. A `?ref=` git source still works, and is a dependency on
this repository at every `init`.

### `azure-private-foundation` (BREAKING for Azure roots)

**Every Azure backing service can be private, and the network moves into a
foundation that is applied first.** PostgreSQL was already VNet-private; the
cache, the storage account and the key vault now are too
(`backing_services_network_access = "private"`, the default), each behind a
private endpoint. There is no VPN: a **management runner** — one small VM in the
VNet, SSH keys only, inbound SSH from an allowlist — is where the substrate's
data-plane resources are applied from, and the Kubernetes API stays public,
narrowed by `cluster_authorized_ip_ranges`.

New:
- `modules/providers/azure/network` — VNet, subnets `aks` / `postgres` /
  `private-endpoints` / `management`, one private DNS zone per private-link
  service (`blob | redis | vault`), linked to the VNet.
- `modules/providers/azure/private-endpoint` — one endpoint for one service,
  registered into its private DNS zone.
- `modules/providers/azure/management-runner` — the runner VM.
- `stacks/azure/xema-foundation` — resource group + network + runner. Its
  `network` output is the substrate's `network` input, unchanged.
- `modules/providers/azure/cache` gains an `id` output (the endpoint's target).

What an Azure consumer root on the previous tag must change:

```hcl
# NEW root, applied FIRST (from anywhere):
module "foundation" {
  source = "github.com/xema-dev/xema-infra-terraform//stacks/azure/xema-foundation?ref=vX.Y.Z"

  deployment_name = "acme-prod"
  region          = "germanywestcentral"
  management_runner = {
    ssh_public_keys   = ["ssh-ed25519 AAAA..."]
    allowed_ssh_cidrs = ["203.0.113.10/32"]
  }
}

# The substrate root, applied FROM THE RUNNER:
module "substrate" {
  # ...
  network                      = <the foundation's `network` output>
  cluster_authorized_ip_ranges = [<your IPs>, <the runner's public_ip_address>]
  # backing_services_network_access = "public" keeps the old reachability
}
```

- **Removed** from `stacks/azure/xema-substrate`: `existing_vnet_id`,
  `existing_delegated_subnet_id` — both are `network` now, in every mode.
- **Removed** from `modules/providers/azure/cluster`: `vnet_address_space`,
  `aks_subnet_prefix`, `postgres_subnet_prefix` (the network module owns them)
  and the `vpc_id` / `delegated_subnet_id` outputs. **Added, required:**
  `vnet_id`, `node_subnet_id`.
- The cluster's resource group now defaults to the network's (the foundation's).
- **State:** a root that already applied the old cluster module holds a VNet and
  two subnets under `module.cluster`; adopting this means `moved` blocks to the
  foundation's addresses or a fresh environment. Measured 2026-09-26: the live
  roots (xema-deploy `terraform/live/xema-prod` on the DigitalOcean stack at
  `v0.5.0`, `cloudflare-edge` at a pinned sha) use no Azure module, and no Azure
  root has been applied, so nothing live is affected.

### `postgres-tenancy`

**`CREATE EXTENSION` stops being a shell on the box.** A new module does
databases, login roles, grants and extensions INSIDE a PostgreSQL server the
module does not own — the counterpart to `providers/<cloud>/managed-postgres`,
which does the same through a cloud control plane for a server it created.

Nothing existing changes: it is additive, and no stack consumes it (the Azure
and DigitalOcean stacks keep doing their own tenancy through their control
planes, with their own state addresses). A consumer whose server is a box's
Postgres, or a Flexible Server another team owns, calls it from its root:

```hcl
module "tenancy" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/postgres-tenancy?ref=vX.Y.Z"

  databases       = ["acme_biomes", "acme_openfga"]
  roles           = ["acme_app"]
  database_owners = { acme_biomes = "acme_app", acme_openfga = "acme_app" }
  connect_grants  = { acme_app = ["acme_biomes", "acme_openfga"] }
  extensions      = { acme_biomes = ["vector", "pg_trgm"] }
}
```

`vector` is not a trusted extension, so a database owner cannot create it and
an application's own migration cannot either — which is why it was being
created with a shell on the host. A server that refuses fails the apply naming
the extension, deliberately: an application booting against a database missing
its extension fails later and further away.

A role granted a database it OWNS receives `CONNECT, TEMPORARY, CREATE`; any
other role receives `CONNECT`. The provider's grant is declarative, so an owner
granted CONNECT alone LOSES CREATE and TEMPORARY — proven against PostgreSQL
18.6 by applying this module and the bootstrap SQL it replaces to two identical
servers and diffing the catalogs: the SQL leaves `<role>=CTc/<role>`, the
CONNECT-only form left `<role>=c/<role>`.

Role passwords are GENERATED and exposed through `role_passwords` (sensitive);
a password supplied as an input has been written somewhere before it reaches
state. Every object is importable, so a server whose databases were created by
a hand-run SQL file adopts without recreating anything — note that an import
does not read a password back, so the first apply after one is a rotation.

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
