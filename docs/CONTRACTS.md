# Substrate contracts

The substrate is decomposed into a small set of **primitives**. Each primitive has
a **cloud-agnostic interface** (the variables it accepts and the outputs it
exposes). A per-cloud module under `modules/providers/<cloud>/<primitive>/` is an
**implementation** of that interface; a stack wires implementations together.

Adopting a new cloud means writing one implementation per primitive that honours
these contracts — the stack, the cloud-agnostic modules, and the extension
mechanism are then reused unchanged.

## Enable / disable toggles — greenfield vs consume

Each substrate area is independently toggleable via an `enable_*` stack input
(`enable_cluster`, `enable_managed_postgres`, `enable_dns`, `enable_rwx_storage`,
`enable_workload_namespaces`, `enable_identity_realm`; all default `true`). A
stack that implements the optional primitives below adds a toggle per primitive
with the same shape (`enable_object_storage`, `enable_secrets_backend`,
`enable_cache`, `enable_ingress_tls`). This splits the **cloud-infra** plane from
the **xema-specific** plane:

- **Greenfield (default):** everything enabled → the stack CREATES the cluster,
  managed DB, DNS, in-cluster addons, and realm from nothing.
- **Xema-specific / consume:** set `enable_cluster = false`,
  `enable_managed_postgres = false`, `enable_dns = false` when a SEPARATE "cloud
  substrate" Terraform owns the cluster / DB / DNS. The stack then manages ONLY
  the xema-specific resources (namespaces, RWX storage, realm, extension claims)
  and **consumes** the existing cluster — it reads the cluster by name
  (`var.cluster_name`) to configure the kube/helm providers, and extension
  `managed_databases` target `var.existing_database_cluster_id`.

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
  DigitalOcean: Azure Database for PostgreSQL Flexible Server presents a
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
- Extra outputs: `name_servers` (delegate the apex to these at the registrar),
  `zone_id`, `resource_group_name`, and — when the optional
  `dns01_workload_identity` input is enabled — `dns01_client_id`, the
  user-assigned identity cert-manager's ACME DNS-01 solver uses through workload
  identity (see the `ingress-tls` addon).

---

## `object-bucket`

A single object-storage bucket (for application/biome use, not Terraform state).

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
  S3 endpoint — the platform's `@xemahq/blob-storage` Azure adapter targets it.
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
extra lock table is needed.

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
| `name` | `string` | Vault name (cloud naming rules apply; globally unique where the cloud requires it). |
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
- **`cluster-addons/workload-namespaces`** — the namespaces that must exist before
  the Helm app bring-up runs.
- **`identity-realm`** — the full Keycloak realm (realm + clients + roles +
  protocol mappers) via the `keycloak` provider.
- **`cluster-addons/secrets`** — materializes operator-provided credentials as
  Kubernetes Secrets (the management-plane "secret backend" Helm values reference
  via `secretKeyRef`), via the `kubernetes` provider.
- **`cluster-addons/ingress-tls`** — the ingress edge every Xema hostname sits
  behind: `ingress-nginx` (a cloud `LoadBalancer`, annotations passed through),
  `cert-manager` plus one ACME `ClusterIssuer` (closed-set solver:
  `http01 | dns01-azure`), and the External Secrets Operator plus one
  `ClusterSecretStore` (closed-set backend: `azure-key-vault`). Chart versions are
  pinned inputs with defaults. Cloud-specific facts (a DNS zone, a vault URI, the
  identities that may touch them) arrive as plain string inputs from the
  provider primitives, so the addon itself installs against any conformant
  cluster via the `helm` provider.
- **extension/biome substrate** — see [extensions.md](extensions.md). Not a
  resource module; a documented claim contract the stack `for_each`-wires to the
  active cloud's `object-bucket` / `managed-postgres` / `dns` primitives.
