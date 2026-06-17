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
`enable_workload_namespaces`, `enable_identity_realm`; all default `true`). This
splits the **cloud-infra** plane from the **xema-specific** plane:

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

---

## `state-bucket` (bootstrap-only)

A bucket dedicated to holding Terraform state for a deployment. Created **once**
during bootstrap, typically with local state, then the backend points at it. Kept
separate from `object-bucket` because its lifecycle and access policy differ (it
holds state, must be private + versioned + locked). See
[CONVENTIONS.md § State & secrets](CONVENTIONS.md).

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
- **extension/biome substrate** — see [extensions.md](extensions.md). Not a
  resource module; a documented claim contract the stack `for_each`-wires to the
  active cloud's `object-bucket` / `managed-postgres` / `dns` primitives.
