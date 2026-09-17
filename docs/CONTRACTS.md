# Substrate contracts

The substrate is decomposed into a small set of **primitives**. Each primitive has
a **cloud-agnostic interface** (the variables it accepts and the outputs it
exposes). A per-cloud module under `modules/providers/<cloud>/<primitive>/` is an
**implementation** of that interface; a stack wires implementations together.

Adopting a new cloud means writing one implementation per primitive that honours
these contracts — the stack, the cloud-agnostic modules, and the extension
mechanism are then reused unchanged.

## The boundary: capabilities, never applications

Everything in this repository must be usable **without the platform running at
all**. It deals in CAPABILITIES — Kubernetes, PostgreSQL, Redis, object
storage, DNS/ingress, secret authority — and knows no application concept: no
service name, no biome, no roster of who runs where. A consumer binds to the
substrate through the [binding contract](#binding-contract) below; it does not
own the infrastructure's architecture, and the infrastructure does not know the
consumer's.

Two consequences decide the shape of every stack input:

- **The database roster and the namespace roster are REQUIRED inputs with no
  default** (`platform_databases`, `workload_namespaces`). Which databases and
  namespaces exist is a fact the consumer derives from what it deploys — from
  its own distribution — so a stack invoked without them refuses to plan. There
  is no per-service switch of any kind: a database exists because the consumer
  listed it, and for no other reason.
- **An extension is a consumer-chosen id.** `extensions` is keyed by a stable
  id the consumer picks; the mechanism (a consumer claims a database, a bucket,
  a DNS record) is generic and the substrate never learns what the id means.

The examples under `examples/<cloud>/` pass explicit rosters. They are
EXAMPLES of one deployment's answer, labelled as such, never a default.

## The capability matrix — EXISTING, MANAGED, or NOT REQUIRED

Every capability a deployment needs is in exactly one of three states, and the
state is a DECLARATION the consumer makes, never something inferred:

- **EXISTING** — the consumer binds to a capability somebody already runs
  (its own DBA's Postgres, a corporate DNS, a shared Keycloak). This module set
  creates nothing for it; the stack's `enable_<area> = false` consumes it, and
  the deployment root declares `provider: external` for it.
- **MANAGED by this module set** — a stack module creates it in the cloud and
  the [binding contract](#binding-contract) publishes its facts.
- **MANAGED in-cluster** — the capability is a Helm recipe the DEPLOYMENT ROOT
  installs (`provider: self-hosted` in its `infra.yaml`), not Terraform. This
  repository stops at the substrate and deploys nothing into the cluster but
  the addons below; a backing service that runs IN the cluster is the
  deployment root's to install, and that root's `infra.yaml` — one
  `<component>.provider` per capability — IS the capability-shaped
  declaration layer.
- **NOT REQUIRED** — the deployment does not use it. Only the capabilities the
  deployment root's `infra.yaml` admits `provider: disabled` for can be in this
  state; the rest are required by every service that boots.

| capability | EXISTING (bind to yours) | MANAGED by this module set | MANAGED in-cluster (deployment root's `infra.yaml`) | NOT REQUIRED |
| --- | --- | --- | --- | --- |
| kubernetes | `enable_cluster = false`, `cluster_name` reads it | `providers/<cloud>/cluster` (DOKS, AKS) | — (it is the cluster) | never |
| postgres | `enable_managed_postgres = false` (+ `existing_database_cluster_id` for extension claims); `infra.yaml#postgres.provider: external` | `providers/<cloud>/managed-postgres`, databases from the REQUIRED `platform_databases` roster | `postgres.provider: self-hosted` chart | never |
| redis | `infra.yaml#redis.provider: external` | `providers/azure/cache` (Azure only; DigitalOcean: no module — bind or self-host) | `redis.provider: self-hosted` (valkey chart) | never |
| object-store | `infra.yaml#minio.provider: external` | `providers/<cloud>/object-bucket` — per EXTENSION claim on DigitalOcean, the platform account + extension claims on Azure | `minio.provider: self-hosted` chart | never |
| etcd | `infra.yaml#etcd.provider: external` (scoped by an etcd namespace per deployment) | **no module** — no cloud here offers it managed | `etcd.provider: self-hosted` chart — the normal answer | never |
| temporal | `infra.yaml#temporal.provider: external` | **no module** | `temporal.provider: self-hosted` chart | `temporal.provider: disabled` — every workflow service fails fast |
| dns / ingress | `enable_dns = false` (DNS at your registrar or another zone owner); ingress edge already present in the cluster | `providers/<cloud>/dns` for the zone; `cluster-addons/ingress-tls` for the edge (ingress-nginx + cert-manager + External Secrets; wired by the Azure stack today) | — | never |
| secret-authority | the deployment root's own generator + an operator-held externals file (the DigitalOcean shape today) | `providers/azure/secrets-backend` (Key Vault + External Secrets reader identity) with `ingress-tls`'s `ClusterSecretStore`; `cluster-addons/secrets` for operator-provided values as plain Secrets | — | never |
| identity-realm | `enable_identity_realm = false`; `infra.yaml#keycloak.provider: external` | `identity-realm` — the REALM inside a Keycloak the consumer already runs (`keycloak_url`); this module set does not install Keycloak | `keycloak.provider: self-hosted` chart installs the server | never |

Two things the table says that are easy to read past:

- **Redis, etcd and temporal MANAGED is the in-cluster recipe.** There is no
  Terraform for them (Azure's cache module is the one exception, and it is
  optional). "MANAGED" for those three is a Helm chart the deployment root
  installs, and the declaration lives in that root's `infra.yaml`, not in any
  stack input. A stack input for them would be this repository learning an
  application's runtime roster, which is the boundary above.
- **`identity-realm` manages a realm, never a server.** `keycloak_url` names a
  Keycloak that already answers; whether that server is EXISTING or a
  self-hosted chart is the deployment root's `keycloak.provider`.

## Engine and authoring profile — the engine is not the definition

**OpenTofu is the default execution engine. HashiCorp Terraform is supported
when the customer mandates it.** The infrastructure definition is standard
HCL; the engine is the binary an operator runs (`cd <root> && tofu init/plan/
apply`, or `terraform …`). There is one module set, never a tofu fork and a
terraform fork, and NO wrapper of any kind — no DSL, no translation layer, no
state layer, no module registry. `cd <root> && tofu|terraform init/plan/apply`
must work with nothing of Xema's installed, or the boundary is wrong. Xema
consumes OUTPUTS (the [binding contract](#binding-contract) and the sensitive
outputs, through `tooling/bind`), and must never care which engine produced
them.

Every module and stack has an **engine profile**, and the profile is a closed
set of two:

| profile | means | how it is recorded |
| --- | --- | --- |
| `terraform-portable` | standard `terraform {}` / providers / modules / variables / outputs; no OpenTofu-only language or state feature; a backend both engines read (Azure Blob, S3-compatible, GCS — backend/provider-native encryption with the customer's KMS; HCP never mandatory); provider versions pinned and resolvable from both ecosystems | **the zero-configuration DEFAULT — recorded NOWHERE.** A module that says nothing is portable, and the customer template only ever uses this |
| `opentofu-native` | uses an OpenTofu-only construct on purpose (client-side state encryption, provider iteration, …); does not advertise portability | **the EXCEPTION, declared** in the module's `versions.tf` beside its `required_version`: `locals { xema_engine_profile = "opentofu-native" }` — no manifest, no header, no registry |

What makes the default data rather than a hope is one check in this
repository's CI, `tooling/check-engine-profile.mjs` (node --test'd): per
module, an OpenTofu-only construct present WITHOUT that local fails, naming
the construct, the file, the line and the module — `encryption {`,
`removed {`, `terraform.applying`, `provider::…(` calls, provider `for_each`,
an engine-naming `required_version`, a `.tofu` file. A module WITH the local
is opentofu-native and is validated on the OpenTofu leg only.

Measured on `origin/develop` `63a9dfd` (2026-09-16): every module is
terraform-portable — zero `encryption {}`, zero `removed {}`, zero
`terraform.applying`, zero `provider::` functions (control: 384 variable
declarations), one `azurerm` backend, `required_version = ">= 1.6"`
throughout. Portability is proven once per module release by CI running
`fmt` + `validate` on BOTH engines for every portable leaf; the
representative-plan half of that proof is unrun in CI because CI holds no
cloud credential and no credential-free plan fixture exists (recorded in
`ci.yml`, not faked). The first two-engine run found one real defect the
Terraform leg alone had never seen: `providers/azure/cluster`'s `endpoint`
output derived from the sensitive `kube_config` block, which OpenTofu's
`validate` refuses and Terraform would have refused at plan — fixed with
`nonsensitive()`, which both engines accept.

## Three ownership modes, one stack

Who owns and who operates the substrate are two axes, and they produce three
OPERATING MODES of one model. The stack is parameter-identical across all
three: what changes is who runs `apply`, with which engine, where the state
lives, and who holds the credentials. No `.tf` differs between modes.

| | 1 — customer-owned, customer-operated | 2 — customer-owned, NeuralChowder-operated | 3 — NeuralChowder-owned, NeuralChowder-operated (vendor-hosted) |
| --- | --- | --- | --- |
| engine | **their choice**; Terraform (and HCP/TFE) fully supported | **OpenTofu**, unless the customer mandates Terraform/HCP | **OpenTofu** |
| runs `apply` | the customer's operator, locally (this repo's CI never applies) | NeuralChowder's operator, locally, under DELEGATED IAM in the customer's account | NeuralChowder's operator |
| consumer root (`main.tf` + `backend.hcl` + tfvars) | the customer's private repository, with the module set VENDORED at a released version (`vendor/xema-infra-terraform-vX.Y.Z/`, from the release tarball or a mirror of this repository in the customer's Git; `init` needs nothing of ours) | the customer's private repository, vendored the same way; NeuralChowder has access to it | NeuralChowder's private repository, `?ref=vX.Y.Z` |
| cloud account | the customer's | **the customer's, from day one** | NeuralChowder's |
| state backend (`backend.hcl`) + KMS / key authority | the customer's bucket and keys (`providers/<cloud>/state-bucket`, bootstrapped once) | **the customer's bucket and keys, from day one** — never the only authoritative copy in a NeuralChowder-only system | NeuralChowder's |
| state-backend credential (`AWS_*` / `ARM_*` for `init`) | the customer's | the customer's, delegated to NeuralChowder | NeuralChowder's |
| provider credentials (`TF_VAR_do_token`, `TF_VAR_keycloak_client_secret`, Azure `ARM_*`) | the customer's cloud account | the customer's, as a scoped delegated identity | NeuralChowder's |
| kubeconfig (`kubeconfig_raw`) | the customer | read by NeuralChowder at apply time, never stored | NeuralChowder |
| DNS authority (`dns_domain` zone) | the customer's registrar delegates to the created zone | same — the zone is in the customer's cloud | NeuralChowder's zone |
| registry pull credential (the deployment root's `ghcr-dockerconfigjson` external) | issued to the customer | held by NeuralChowder | held by NeuralChowder |
| SCM credential (the private consumer root) | the customer's | the customer's, with NeuralChowder as a collaborator | NeuralChowder's |

What every mode has in common decides the design: the stack reads its inputs
from tfvars and the environment, keeps facts in one state, and publishes one
[binding contract](#binding-contract). Nothing in it knows which mode it is in.

### Onboarding asks TWO lines

1. **"Does the customer mandate Terraform / HCP?"** — yes → the engine is
   `terraform`; no → `tofu`.
2. **"Is future Terraform portability required?"** — default **yes** for
   customer-owned infrastructure; it pins the profile to `terraform-portable`,
   which is the only profile the customer template uses anyway.

No further ceremony. `examples/customer/README.md` carries both lines.

### Mode 2 → 1 handoff: revoke access + hand over the runbook, NEVER a state migration

Because in mode 2 the cloud account, the state backend and the keys are the
customer's from day one, handing operation to the customer is the REMOVAL of
NeuralChowder's delegated access plus the runbook — the state does not move,
because it was never anywhere else. Acceptance, all four:

- the customer holds the IaC source (the consumer root: module version,
  tfvars, `backend.hcl`);
- the customer holds the state backend and its keys, and the cloud
  credentials;
- the customer can run the declared engine independently — a clean
  `tofu plan` (or `terraform plan`) from their own workstation, with
  NeuralChowder's access already revoked;
- for the `terraform-portable` profile, switching control to Terraform
  proposes NO destructive recreation (the procedure below).

### Switching the engine to Terraform (portable profile): a controlled operation

Never casually alternate both CLIs on one live state. When the customer takes
operation on Terraform, in order:

1. **Freeze** — no `apply` from anyone until the switch completes.
2. **Back up the state** (`tofu state pull > backup.tfstate`, kept by the
   customer).
3. **Clean OpenTofu plan** — `tofu plan` reports `0 to add, 0 to change, 0 to
   destroy`; a dirty plan is fixed before, never during.
4. **Verify no OpenTofu-only feature or state dependency** —
   `node tooling/check-profile.mjs` says `terraform-portable` for every leaf
   the root consumes; no `encryption {}`, no provider iteration.
5. **Init the customer's Terraform tooling and backend** — `terraform init
   -backend-config=backend.hcl` against the SAME backend (`backend.hcl`
   unchanged; the state does not move).
6. **`terraform plan` — require NO unexpected recreation.** Provider version
   pins resolve identically from both ecosystems; anything that wants to
   create, replace or destroy is a stop, not a note.
7. **Transfer / revoke access** — the customer's operator is now the one who
   applies; NeuralChowder's delegated identity is revoked.

### Mode 2 → 3 (and 3 → 2): a change of BINDINGS, never a replatform

Moving between NeuralChowder-operated-in-the-customer's-account and
vendor-hosted is a different operation from the handoff above, because here
the cloud ACCOUNT changes. It is the ordered transfer of the bindings in the
table, and nothing else:

1. **State backend + its credential** — copy the state into the receiving
   account's bucket (`state pull` / `push`, or `init -migrate-state` against
   the new `backend.hcl`), then revoke the old backend credential.
2. **Provider token(s)** — the receiving account's cloud credential replaces
   the issuing one in `TF_VAR_*` / `ARM_*`; `plan` must report **0 to add, 0
   to change, 0 to destroy**.
3. **kubeconfig** — re-read from `output -raw kubeconfig_raw` by the receiving
   party; the issuing party deletes its copy.
4. **DNS authority** — re-create the zone (`dns_domain`) in the receiving
   account and re-delegate at the registrar (`dns_name_servers` on Azure).
5. **Registry pull credential** — re-issued to the receiving party and
   re-supplied through the deployment root's externals file; the old one
   revoked.
6. **SCM credential** — ownership of the private consumer root moves.

The assertion that makes either operation a handoff and not a migration: **no
`.tf` file changes**. Only `backend.hcl` and the ownership of tfvars and
credentials change, so `plan` after the credential moves is the proof — a plan
that wants to create, replace or destroy anything means a parameter moved,
and that is a defect to fix before proceeding.

What this does NOT cover, stated so nobody reads the table as complete: the
deployment root (Helm GitOps) has its own bindings — its cluster credential,
its image registry, its secret generator's externals — and they move under
that root's own procedure. This section is the substrate's half only.

## Enable / disable toggles — greenfield vs consume

Each substrate area is independently toggleable via an `enable_*` stack input
(`enable_cluster`, `enable_managed_postgres`, `enable_dns`, `enable_rwx_storage`,
`enable_workload_namespaces`, `enable_identity_realm`; all default `true`). A
stack that implements the optional primitives below adds a toggle per primitive
with the same shape (`enable_object_storage`, `enable_secrets_backend`,
`enable_cache`, `enable_ingress_tls`). This splits the **cloud-infra** plane from
the **in-cluster + identity** plane:

- **Greenfield (default):** everything enabled → the stack CREATES the cluster,
  managed DB, DNS, in-cluster addons, and realm from nothing.
- **Consume:** set `enable_cluster = false`, `enable_managed_postgres = false`,
  `enable_dns = false` when a SEPARATE "cloud substrate" Terraform owns the
  cluster / DB / DNS. The stack then manages ONLY the in-cluster and identity
  resources (namespaces, RWX storage, realm, extension claims) and **consumes**
  the existing cluster — it reads the cluster by name (`var.cluster_name`) to
  configure the kube/helm providers, and extension `managed_databases` target
  `var.existing_database_cluster_id`.

A disabled cloud module is `count`-gated to zero (consumed, never destroyed).

> **Rule:** an implementation MAY add cloud-specific *optional* inputs (with
> defaults) and MAY expose extra outputs, but it MUST accept every required input
> and expose every required output below, with the same name, type, and meaning.
> Closed-set inputs use enums validated with a `validation` block — never a
> free-form string.

---

## `cluster`

Provisions the managed Kubernetes cluster and its node pools.

**Required inputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `name` | `string` | Cluster name. |
| `region` | `string` | Cloud region. |
| `kubernetes_version` | `string` | Control-plane version (e.g. `"1.31"`). |
| `node_pools` | `map(object({ size = string, node_count = number, min_nodes = optional(number), max_nodes = optional(number), labels = optional(map(string), {}), taints = optional(list(object({ key = string, value = string, effect = string })), []) }))` | Node pools keyed by a stable pool id (e.g. `generic`, `workers`). |
| `tags` | `optional(map(string), {})` | Resource tags/labels. |

**Required outputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `cluster_id` | `string` | Provider id of the cluster (for imports & references). |
| `endpoint` | `string` | Kubernetes API server URL. |
| `kubeconfig_raw` | `string` (sensitive) | Raw kubeconfig YAML. |
| `cluster_ca_certificate` | `string` (sensitive) | Base64 CA cert. |
| `token` | `string` (sensitive) | Short-lived auth token, if the cloud issues one (else `""`). |
| `vpc_id` | `string` | Network the cluster lives in (`""` if N/A). |

**Azure specifics** (`providers/azure/cluster`)

- `region` is the Azure *location* (e.g. `"westeurope"`).
- `token` is always `""`: AKS issues **client-certificate** credentials, not a
  bearer token. The implementation exposes the extra sensitive outputs
  `client_certificate` and `client_key`, which the stack feeds to the
  `kubernetes` / `helm` providers instead of `token`.
- `vpc_id` is the **virtual network** id. The module always creates its own VNet
  with two subnets — one for AKS, one **delegated** to
  `Microsoft.DBforPostgreSQL/flexibleServers` — and exposes the extras
  `delegated_subnet_id`, `resource_group_name`, `oidc_issuer_url`
  (workload identity is always ON) and `kubelet_identity_id`.
- `node_pools` keys are also the AKS **agent pool names**, so they must match
  `^[a-z][a-z0-9]{0,11}$`. The default pool cannot carry taints (an AKS rule);
  put tainted pools in additional pools.

---

## `managed-postgres`

Provisions a managed Postgres instance/cluster plus logical databases and roles.

**Required inputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `name` | `string` | Database cluster name. |
| `region` | `string` | Cloud region. |
| `engine_version` | `string` | Major Postgres version (e.g. `"16"`). |
| `size` | `string` | Instance size/SKU. |
| `node_count` | `optional(number, 1)` | Replica count (1 = single node). |
| `vpc_id` | `optional(string)` | Network to attach to, when the cloud supports private networking. |
| `databases` | `optional(set(string), [])` | Logical databases to ensure exist. |
| `roles` | `optional(set(string), [])` | Logical roles to ensure exist. |
| `tags` | `optional(map(string), {})` | Resource tags. |

**Required outputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `cluster_id` | `string` | Provider id (for imports). |
| `host` | `string` | Private host (preferred) or public host. |
| `port` | `number` | Port (5432 typical). |
| `uri` | `string` (sensitive) | Admin connection URI. |
| `ca_certificate` | `string` (sensitive) | CA bundle for `verify-full`, `""` if N/A. |

**Azure specifics** (`providers/azure/managed-postgres`)

- `size` is the Flexible Server **SKU name** (e.g. `"B_Standard_B2s"`,
  `"GP_Standard_D2ds_v5"`).
- `node_count` accepts only `1` (single zone) or `2` (zone-redundant high
  availability, one standby). Azure has no N-replica flexible server.
- `vpc_id` is the virtual network to **link the private DNS zone** to; private
  access additionally needs the extra `delegated_subnet_id` (the cluster
  module's `delegated_subnet_id` output). Access mode is the closed set
  `network_access = private | public` — never inferred.
- `ca_certificate` is always `""`, and that is **not** a gap the way it is on
  DigitalOcean: Azure Database for PostgreSQL Flexible Server serves a
  certificate chain anchored on **public root CAs** (DigiCert Global Root G2 /
  Microsoft RSA Root CA 2017), which every OS trust store already carries.
  `sslmode=verify-full` therefore works with the system bundle and there is no
  per-server CA to export.
- Roles are created **inside** the server with the `cyrilgdn/postgresql`
  provider (Azure's API has no logical-role resource), so the **stack** must
  configure that provider against the server's admin credentials and must be
  able to **reach** the server (a private server is reachable only from inside
  the VNet or over VPN/bastion). Every role gets `CONNECT` on every database and
  `CONNECT` is revoked from `PUBLIC`. Per-role `create_database` /
  `connection_limit` come from the optional `role_options` map.

---

## `dns`

Manages a DNS zone's records.

**Required inputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `domain` | `string` | Managed zone apex (e.g. `xema.dev`). |
| `records` | `map(object({ name = string, type = optional(string, "A"), value = string, ttl = optional(number, 300) }))` | Records keyed by a stable id. |

**Required outputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `domain` | `string` | The managed zone. |
| `record_ids` | `map(string)` | Provider record ids keyed by the input key. |

**Azure specifics** (`providers/azure/dns`)

- Record `type` is the closed set `A | AAAA | CNAME | TXT` (Azure DNS uses one
  resource type per record type; only those four are implemented). Wildcards
  (`"*"`, `"*.sub"`) and the apex (`"@"`) are supported.
- The zone is global, but a created resource group and the DNS-01 identity
  need a location, so the implementation adds an optional `region` that is
  required (by precondition, naming the input) exactly when one of those is
  created.
- Extra outputs: `name_servers` (delegate the apex to these at the registrar),
  `zone_id`, `resource_group_name`, `subscription_id`, and — when the optional
  `dns01_workload_identity` input is enabled — `dns01_client_id`, the
  user-assigned identity cert-manager's ACME DNS-01 solver uses through workload
  identity (see the `ingress-tls` addon).

---

## `object-bucket`

A single object-storage bucket (for application/extension use, not Terraform state).

**Required inputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `name` | `string` | Globally-unique bucket name. |
| `region` | `string` | Bucket region. |
| `acl` | `optional(string, "private")` | One of `private` \| `public-read` (validated). |
| `versioning` | `optional(bool, false)` | Enable object versioning. |

**Required outputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `bucket` | `string` | Bucket name. |
| `endpoint` | `string` | S3-compatible endpoint URL. |

**Azure specifics** (`providers/azure/object-bucket`)

- The "bucket" is a **storage account** (`name` must match `^[a-z0-9]{3,24}$`
  and be globally unique); `endpoint` is its primary **Blob** endpoint, not an
  S3 endpoint — a consumer's Azure blob adapter targets it.
- **Global uniqueness is across every Azure tenant**, because the name is a
  public DNS label (`<name>.blob.core.windows.net`). A stack that DERIVES the
  name must therefore also let it be overridden: the Azure stack derives
  `<deployment_name without hyphens>blob` and takes `storage_account_name` to
  replace it, validated against the same rule. Extension-claimed buckets carry
  their own explicit `name` and need no override.
- Blob **containers** are optional (`containers = set(string)`): the platform
  ensures its own `${prefix}-${logical}` containers at boot, so pre-creating
  them here is only needed when the runtime identity may not create containers.
- `acl = "public-read"` maps to `container_access_type = "blob"` on each
  container and `allow_nested_items_to_be_public = true` on the account.
- Replication is the closed set `LRS | ZRS | GRS | GZRS`.

---

## `state-bucket` (bootstrap-only)

A bucket dedicated to holding Terraform state for a deployment. Created **once**
during bootstrap, typically with local state, then the backend points at it. Kept
separate from `object-bucket` because its lifecycle and access policy differ (it
holds state, must be private + versioned + locked). See
[CONVENTIONS.md § State & secrets](CONVENTIONS.md).

**Azure specifics** (`providers/azure/state-bucket`): a storage account plus one
private, versioned **container** (default `tfstate`); `backend_config_hint`
emits a `backend "azurerm" {}` block. Locking is native (blob leases), so no
extra lock table is needed. The account `name` is a globally-unique storage
account name (`^[a-z0-9]{3,24}$`) that the bootstrap caller supplies explicitly
— the stack never derives it, since the backend is the consuming root's.

---

## `secrets-backend` (optional)

A cloud secret store the cluster reads at runtime through the
[External Secrets Operator](https://external-secrets.io) — the source that the
`ingress-tls` addon's `ClusterSecretStore` points at. Optional: a deployment may
instead materialize secrets with `cluster-addons/secrets`. Not every cloud has
an implementation; today only Azure (Key Vault).

**Required inputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `name` | `string` | Vault name (cloud naming rules apply; globally unique where the cloud requires it — see the Azure specifics: a stack that derives it must also accept an override). |
| `region` | `string` | Cloud region. |
| `secret_names` | `optional(set(string), [])` | Secrets to **seed** at provisioning time, by name. |
| `secret_values` | `map(string)` (sensitive, **no default**) | Values for every name in `secret_names`. A name with no value fails fast. Never committed — supply via `TF_VAR_*` / a decrypted tfvars. |
| `workload_identity` | `object({ enabled = bool, oidc_issuer_url = string, service_account_namespace = optional(string), service_account_name = optional(string) })` | Federate the cluster's OIDC issuer to an identity that may **read** secrets, for the in-cluster operator's service account. |
| `tags` | `optional(map(string), {})` | Resource tags. |

**Required outputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `vault_uri` | `string` | The vault's base URI the operator targets. |
| `client_id` | `string` | Client id of the reader identity (`""` when `workload_identity.enabled = false`). |
| `tenant_id` | `string` | Identity tenant the reader identity lives in (`""` if the cloud has no such notion). |

**Azure specifics** (`providers/azure/secrets-backend`): an `azurerm_key_vault`
with **RBAC authorization** (no access policies), one `azurerm_key_vault_secret`
per seeded name, and a user-assigned identity + federated credential
(`api://AzureADTokenExchange`) holding **Key Vault Secrets User**. The principal
running Terraform is granted **Key Vault Secrets Officer** on the vault so the
seeded secrets can be written; role propagation is waited on explicitly rather
than retried by hand.

The vault `name` is **globally unique across every Azure tenant** (it is the
DNS label of `<name>.vault.azure.net`; 3-24 letters, digits and single hyphens,
starting with a letter). A derived name can collide with a vault somebody else
owns, and Azure refuses the create only at apply time — so the Azure stack
derives `<deployment_name>-kv` AND takes `key_vault_name` to replace it,
validated against the module's own rule. The dedicated resource group follows
the vault name (`<name>-rg`). The same holds for the other two globally-unique
derived names the stack owns — `postgres_server_name` and `redis_cache_name`.

---

## `cache` (optional)

A managed Redis-protocol cache. Optional: the platform's default topology runs
valkey **in-cluster** via Helm; use this only when a deployment wants the cloud's
managed offering instead. Today only Azure (Azure Cache for Redis).

**Required inputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `name` | `string` | Cache name. |
| `region` | `string` | Cloud region. |
| `sku` | `string` | Closed set, per implementation (Azure: `Basic \| Standard \| Premium`). |
| `capacity` | `optional(number, 1)` | Size step within the SKU. |
| `tags` | `optional(map(string), {})` | Resource tags. |

**Required outputs**

| Name | Type | Meaning |
| --- | --- | --- |
| `host` | `string` | Hostname. |
| `port` | `number` | **TLS** port (Azure: 6380; the non-TLS port is disabled). |
| `primary_key` | `string` (sensitive) | Access key (`""` if the cloud uses identity auth only). |

---

## Cloud-agnostic modules (no per-cloud implementation needed)

These work against any conformant Kubernetes cluster / Keycloak and are reused by
every cloud's stack:

- **`cluster-addons/rwx-storage`** — a ReadWriteMany `StorageClass` backed by an
  NFS provisioner, installed via the `helm` + `kubernetes` providers.
- **`cluster-addons/workload-namespaces`** — a roster of namespaces that must
  exist before anything applies workloads. The roster is a required input; the
  module knows nothing about who lives in a namespace.
- **`cluster-addons/shared-templates-volume`** — a ReadWriteMany NFS export
  shared across N namespaces: one namespace owns (writes) the tree, any number
  mount (read) it, one static PV + PVC pair per namespace, all on the same
  export. The owner, the consumers and every claim name are required inputs.
- **`identity-realm`** — the full Keycloak realm (realm + clients + roles +
  protocol mappers) via the `keycloak` provider.
- **`cluster-addons/secrets`** — materializes operator-provided credentials as
  Kubernetes Secrets (the management-plane "secret backend" Helm values reference
  via `secretKeyRef`), via the `kubernetes` provider.
- **`cluster-addons/deployer-identity`** — the namespaces a deployment owns, the
  least-privileged ServiceAccount its pipeline deploys as, that account's token,
  and the three facts that identify the cluster (endpoint, sha256 of the decoded
  CA, `kube-system` UID). A pipeline's kubeconfig is a credential only a
  cluster-admin can mint, so it belongs in the apply that creates the cluster and
  comes out as an OUTPUT — not a manifest somebody applies by hand once per
  deployment. The namespace is a required input: it is what the deployment
  DECLARES, never something derived from a directory name.
- **`cluster-addons/ingress-tls`** — the ingress edge every hostname on the
  deployment sits behind: `ingress-nginx` (a cloud `LoadBalancer`, annotations passed through),
  `cert-manager` plus one ACME `ClusterIssuer` (closed-set solver:
  `http01 | dns01-azure`), and the External Secrets Operator plus one
  `ClusterSecretStore` (closed-set backend: `azure-key-vault`). Chart versions are
  pinned inputs with defaults. Cloud-specific facts (a DNS zone, a vault URI, the
  identities that may touch them) arrive as plain string inputs from the
  provider primitives, so the addon itself installs against any conformant
  cluster via the `helm` provider. The two object names a consumer's manifests
  reference — `cluster_issuer_name` (default `letsencrypt`, the
  `cert-manager.io/cluster-issuer` annotation) and `cluster_secret_store_name`
  (default `platform`, every `ExternalSecret`'s `secretStoreRef.name`) — are
  validated DNS-1123 inputs echoed as outputs; a stack exposes both as its own
  inputs and outputs (and in its `substrate` map) so a consumer reads the names
  from the stack rather than restating them.
- **extension substrate** — see [extensions.md](extensions.md). Not a resource
  module; a documented claim contract the stack `for_each`-wires to the active
  cloud's `object-bucket` / `managed-postgres` / `dns` primitives, keyed by a
  consumer-chosen extension id.

---

## Binding contract

Every stack exposes ONE output, `substrate`, and it is the only thing a consumer
needs to read to bind itself to the substrate: a map of non-secret facts with
the SAME key shape on every cloud. Credentials are never in it — they are the
stack's separate `sensitive` outputs, read on purpose. A key is `null` when its
area is disabled (`enable_* = false`), consumed elsewhere, or not modelled on
that cloud; a consumer branches on `null`, never on which cloud it is on.

| Key | Type | Meaning | Azure | DigitalOcean |
| --- | --- | --- | --- | --- |
| `deployment_name` | `string` | the one name the stack derives from | derived | `null` (nothing derived) |
| `environment` | `string` | `dev \| prod` | input | `null` (no environment axis) |
| `region` | `string` | cloud region | input | input |
| `tenant_id` | `string` | identity tenant of the secrets reader identity | secrets backend | `null` |
| `cluster_name` | `string` | the created or consumed cluster's name | derived/override | input, `null` when `""` |
| `cluster_resource_group_name` | `string` | the cluster's resource group | created/derived | `null` |
| `oidc_issuer_url` | `string` | the cluster's OIDC issuer for federated identities (`""` when no cluster facts were needed) | cluster | `null` |
| `storage_class_name` | `string` | the ReadWriteMany StorageClass | rwx addon | rwx addon |
| `namespaces` | `set(string)` | the roster ensured on the cluster — exactly `workload_namespaces`; carries NO roles, which namespace plays which part is the consumer's own knowledge | namespaces addon | namespaces addon |
| `postgres_host` / `postgres_port` | `string` / `number` | the created server | managed postgres | managed postgres |
| `postgres_app_role` | `string` | the application role the stack created | managed postgres | `null` (roles are a flat input, `postgres_roles`) |
| `postgres_provisioner_role` | `string` | the role that may CREATE databases at runtime | managed postgres | `null` |
| `postgres_databases` | `set(string)` | the databases ensured on the created server — `platform_databases` after that stack's naming rule (Azure prefixes `<deployment_name>_`; DigitalOcean uses the names verbatim) | managed postgres | managed postgres |
| `blob_account` / `blob_endpoint` / `blob_container_prefix` | `string` | the platform object-storage account, its endpoint, the container prefix | object storage | `null` (no platform bucket; extension buckets are the separate `extension_buckets` output) |
| `key_vault_name` / `key_vault_uri` / `external_secrets_client_id` | `string` | the secrets backend and the identity that reads it | secrets backend | `null` |
| `cluster_secret_store_name` | `string` | the `ClusterSecretStore` every `ExternalSecret` names | ingress addon + secrets backend | `null` |
| `redis_host` / `redis_port` | `string` / `number` | the managed cache (TLS port) | cache | `null` |
| `dns_zone` | `string` | the managed zone apex | dns | dns |
| `dns_name_servers` | `list(string)` | delegate the apex to these | dns | `null` (DigitalOcean's are fixed) |
| `ingress` | `object({ service_name, namespace, class_name, cluster_issuer_name })` | the ingress edge the consumer's `Ingress` objects target | ingress addon | `null` |
| `keycloak_url` / `realm_name` | `string` | the identity realm and where it lives | identity realm | identity realm |

Adding a key is a change to BOTH stacks in the same commit — a consumer must be
able to read the same shape on every cloud, and a key present on one stack only
is a cloud leaking into the contract. A new cloud's stack exposes the same map,
filling what it models and `null` for the rest.
