# `xema-substrate` stack — Azure

Composes the full substrate on Azure from the per-cloud primitives and the
cloud-agnostic addons. **Every name is derived from one input,
`deployment_name`** (see [Derived names](#derived-names)); nothing in this stack
names a deployment, a service or an application. The two rosters the
substrate cannot know — which databases and which namespaces exist — are
**required inputs with no default**, `platform_databases` and
`workload_namespaces`; the consumer derives them from what it deploys (see
[the boundary](../../../docs/CONTRACTS.md#the-boundary-capabilities-never-applications)).

| Module | What it provisions |
| --- | --- |
| `module.cluster` | AKS cluster + node pools + VNet (AKS subnet, Postgres-delegated subnet), workload identity on |
| `module.postgres` | PostgreSQL Flexible Server + the `platform_databases` roster (prefixed) and the derived roles |
| `module.postgres_tenancy` | consume mode: the same prefixed databases and derived roles, ensured inside the EXISTING server over SQL — one stack instance per environment on a shared server; admin password read from Key Vault |
| `module.dns` | the `apex_domain` zone's records (+ the cert-manager DNS-01 identity when that solver is used) |
| `module.blob` | the storage account the platform's blob adapter targets |
| `module.secrets_backend` | Key Vault + the External Secrets reader identity |
| `module.cache` | (optional, off by default) Azure Cache for Redis |
| `module.rwx_storage` | a ReadWriteMany `StorageClass` over the built-in Azure Files CSI driver (NFS) |
| `module.workload_namespaces` | the `workload_namespaces` roster the consumer supplies |
| `module.gateway_tls` | Gateway API CRDs + NGINX Gateway Fabric + Gateway (or a customer-managed Gateway) + cert-manager/ClusterIssuer |
| `module.identity_realm` | the Keycloak realm **container** (+ optional base clients/roles/mappers) |
| `module.extension_bucket` | dedicated storage accounts claimed by extensions (see below) |

> **Realm boundary:** when the consumer's own identity service reconciles the
> realm's clients/roles/scopes/mappers on boot, leave `realm_clients` /
> `realm_roles` / `realm_protocol_mappers` **empty** and let Terraform manage only
> the realm container — see the
> [`identity-realm` README](../../../modules/identity-realm/README.md#ownership-boundary--terraform-vs-identity-api-read-this).

It configures five providers (`azurerm`, `postgresql`, `kubernetes`, `helm`,
`keycloak`) in `providers.tf` — reusable modules never declare a `provider {}`
block, so the root owns provider config and passes it down. Azure
authentication is the provider's own chain (`az login`, `ARM_*`, managed
identity, OIDC); no credential is an input here.

## Derived names

| From `deployment_name = "acme-dev"` | Value | Rule |
| --- | --- | --- |
| resource group / cluster | `acme-dev-rg`, `acme-dev-aks` | verbatim |
| Postgres server / Key Vault / Redis | `acme-dev-pg`, `acme-dev-kv`, `acme-dev-redis` | verbatim |
| storage account | `acmedevblob` | hyphens removed (Azure allows alphanumerics only) |
| Keycloak realm, `BLOB_CONTAINER_PREFIX` | `acme-dev` | verbatim |
| databases | `acme_dev_<name>` for every `<name>` in `platform_databases` | `-` → `_` (Postgres identifiers), then `_<name>` |
| roles | `acme_dev` (app), `acme_dev_provisioner` (CREATEDB) | `-` → `_` |
| namespaces | **not derived** — `workload_namespaces` is passed by full name | none |

`deployment_name` is validated (3-20 chars, lowercase, single hyphens) so every
derived name fits its Azure limit; the hyphen-to-underscore mapping for Postgres
is the one rewrite, and it is injective on that alphabet. `environment`
(`dev | prod`) decides the irreversible knobs: Key Vault purge protection and
the backup retention window are `prod`-only.

### The two rosters — required, never derived

| Input | What it is | Rule |
| --- | --- | --- |
| `platform_databases` | the logical databases to ensure on the created server, UNPREFIXED (`"identity"`, `"billing"`, …) | each becomes `<deployment_name as _>_<name>`; validated `^[a-z][a-z0-9_]{0,42}$`; with `enable_managed_postgres = false` the same names and roles are ensured on the existing server (`module.postgres_tenancy`), or nothing when `[]` |
| `workload_namespaces` | the namespaces to ensure exist, by FULL name | DNS-1123 labels; nothing is derived from `deployment_name`; ignored when `enable_workload_namespaces = false` |

Both have **no default**: which databases and namespaces a deployment needs is
a fact about what it deploys, derived by the consumer from its own
distribution, and a stack invoked without them refuses to plan. There is no
per-database switch — a database exists because it is in the list. A consumer
that wants `<deployment_name>-<role>` namespaces spells that out itself.

**A consumer root must declare the rosters too.** An `.auto.tfvars.json`
carries the roster fine — it sets ROOT variables, so a consumer must ALSO
declare `platform_databases` / `workload_namespaces` as root variables and
pass them into the module call, or it fails with "The argument is required".
`examples/customer/` is the shape — both declared in the root's `variables.tf`
and passed through in `main.tf`.

### Overriding the globally-unique names

Four of the derived names are unique across **every** Azure tenant, not just
this one, because each is a public DNS label — so a derived name can collide
with a resource somebody else owns, and Azure refuses the create at apply time.
Each takes an optional override, validated against the same rule the provider
module enforces; empty (the default) keeps the derived name:

| Input | Derived default | Rule | Public name |
| --- | --- | --- | --- |
| `key_vault_name` | `acme-dev-kv` | 3-24 letters/digits/single hyphens, starts with a letter | `<name>.vault.azure.net` (resource group `<name>-rg`) |
| `storage_account_name` | `acmedevblob` | `^[a-z0-9]{3,24}$` | `<name>.blob.core.windows.net` |
| `postgres_server_name` | `acme-dev-pg` | 3-63 lowercase letters/digits/hyphens, starts with a letter | `<name>.postgres.database.azure.com` (the private DNS zone and derived host follow it) |
| `redis_cache_name` | `acme-dev-redis` | 1-63 letters/digits/hyphens | `<name>.redis.cache.windows.net` |

The AKS cluster name is resource-group-scoped, not global; its override
(`cluster_name`) exists for consume mode, not for collisions. Extension-claimed
storage accounts carry their own explicit `name`.

### The in-cluster names a consumer's manifests reference

`cluster_issuer_name` (default `letsencrypt`) and `cluster_secret_store_name`
(default `platform`) are threaded to the `gateway-tls` addon, validated as
DNS-1123 subdomain names, and **read back** as the stack outputs of the same
name (and in the `substrate` map: `substrate.gateway.cluster_issuer_name`,
`substrate.cluster_secret_store_name`). A consumer's `Gateway`
(`cert-manager.io/cluster-issuer`) and `ExternalSecret` (`secretStoreRef.name`)
manifests should read them from the stack, never restate the defaults. Both
outputs are `null` exactly when the object does not exist — `enable_gateway_tls
= false`, or for the store also `enable_secrets_backend = false`.

## The `substrate` output — the binding contract

One non-secret map a consumer binds to, with the key shape every cloud's stack
shares — documented once in
[`docs/CONTRACTS.md` § Binding contract](../../../docs/CONTRACTS.md#binding-contract).
Every key is `null` when its area is disabled or consumed elsewhere.
`namespaces` is the roster as ensured, and it carries no roles: which namespace
plays which part is the consumer's knowledge, not the substrate's. Credentials
are the separate **sensitive** outputs (`postgres_uri`,
`postgres_role_passwords`, `blob_primary_access_key`, `redis_primary_key`,
`realm_client_secrets`, `kubeconfig_raw`), on purpose.

## The network comes from the foundation — apply it first

The VNet is **not** created here. `stacks/azure/xema-foundation` owns it — the
network, one private DNS zone per private-link service, and the **management
runner** — and this stack takes the foundation's `network` output as its
`network` input, unchanged. The order is fixed by what each step can reach:

| step | what | run from | why there |
| --- | --- | --- | --- |
| 0 | `modules/providers/azure/state-bucket` | anywhere, once | the backend every later step writes its state to |
| 1 | `stacks/azure/xema-foundation` | anywhere | touches only the Azure control plane |
| 2 | **this stack** | **the management runner** | PostgreSQL roles and Key Vault secrets are written INSIDE services with no public endpoint |

`backing_services_network_access` (`private` by default, like
`postgres_network_access`) turns the cache's, storage account's and key vault's
public endpoints off and attaches one private endpoint each, in the
foundation's `private-endpoints` subnet. The Kubernetes API stays public,
narrowed by `cluster_authorized_ip_ranges` — include the runner's public IP
(the foundation's `management_runner.public_ip_address`) so the runner can
reach it too.

## Two modes — greenfield vs consume

Every area is **independently toggleable** via an `enable_*` input:

| Input | Default | What it gates |
| --- | --- | --- |
| `enable_cluster` | `true` | Create AKS (in `network`). `false` ⇒ read the existing cluster by `cluster_name` / `cluster_resource_group_name`. |
| `enable_managed_postgres` | `true` | Create the Flexible Server (and, with `enable_secrets_backend`, write its admin password to this stack's Key Vault). `false` ⇒ the tenancy and extension databases go to `existing_postgres_server_id` / `existing_postgres_host`, with the admin password READ from Key Vault — see [Consume mode: the existing server](#consume-mode-the-existing-server). |
| `enable_dns` | `true` | Manage the `apex_domain` zone. `false` ⇒ DNS owned elsewhere (extension `dns_records` and `dns01-azure` then fail fast). |
| `enable_object_storage` | `true` | Create the blob storage account. |
| `enable_secrets_backend` | `true` | Create the Key Vault + reader identity (and, with it, the External Secrets store). |
| `enable_cache` | `false` | Create a managed Redis. Off: the platform runs valkey in-cluster. |
| `enable_container_registry` | `false` | Create a Premium, private-only container registry with `AcrPull` for the kubelet identity (needs `acr` in the foundation's `private_link_services`, in its default). The CI identity that pushes is **not** created: grant `AcrPush` to your own CI principal on `container_registry_id`. |
| `enable_rwx_storage` | `true` | Create the RWX `StorageClass` on the (created or consumed) cluster. |
| `enable_workload_namespaces` | `true` | Ensure the `workload_namespaces` roster exists. |
| `enable_gateway_tls` | `true` | Install the Gateway API edge (needs `acme_email`; `gateway_hostname` and non-empty `workload_namespaces` with `nginx-gateway-fabric`). The stack output `gateway_parent_ref` is the parentRef every HTTPRoute attaches to. |
| `enable_identity_realm` | `true` | Manage the Keycloak realm (needs a reachable `keycloak_url`). |

`postgres_extensions` (default `[]`) allow-lists PostgreSQL extensions on the
created server (`azure.extensions`, lowercase identifiers); empty writes no
parameter, so Azure's default stands.

`postgres_zone` (default `null`) pins the managed PostgreSQL server to zone "1", "2" or "3"; null keeps
the regional placement. Set it before the first apply: changing it later replaces the server.

A disabled cloud module is `count`-gated to zero — the stack **consumes** the
existing resource instead of creating it; it never plans a destroy. `network`
is required in both modes whenever the stack creates something that lives in
it (the cluster, a private PostgreSQL server, a private backing service).

## Consume mode: the existing server

With `enable_managed_postgres = false` and something to ensure on the existing
server — a non-empty `platform_databases`, or an extension `managed_databases`
claim — this stack connects to that server **over SQL**, as
`existing_postgres_admin_login`. With neither, it reads nothing and connects to
nothing.

**The admin password is read from Key Vault, by reference.** An instance that
CREATES a server (`enable_managed_postgres = true`, `enable_secrets_backend =
true`) writes the server's admin password into its own vault under
`postgres_admin_password_secret_name` (default `postgres-admin-password`). A
consuming instance reads it with an `azurerm_key_vault_secret` data source from
`existing_postgres_admin_password_key_vault_id` under the same name — so the
defaults match with no coordination. There is no password input, and no
`terraform_remote_state`: a typed password has been written somewhere before it
reaches state, and a remote-state read couples this root to another root's
backend. The principal running Terraform needs **Key Vault Secrets User** on
that vault. A creating instance with `enable_secrets_backend = false` has no
vault to write to; its admin password stays only in its state.

| missing, with SQL to run | refused before the read, naming |
| --- | --- |
| `existing_postgres_host` / `existing_postgres_admin_login` | both inputs |
| `existing_postgres_admin_password_key_vault_id` | the input and the secret name it would read |

**Run consume mode where the server's host resolves.** Terraform connects
straight to `existing_postgres_host`, so for a private server it must run on an
**in-VNet runner** (the foundation's management runner) whose VNet is linked to
the server's private DNS zone (`<server>.private.postgres.database.azure.com`)
— and, if the vault is private too, to `privatelink.vaultcore.azure.net`.
Nothing here checks resolution up front — the stack uses no DNS-lookup
provider, and one is not added just for a pre-flight. The provider connects
lazily, so `plan` passes from the wrong place and the APPLY stops at the first
`postgresql_*` resource with:

```
Error: error connecting to PostgreSQL server <host> (scheme: postgres): dial tcp: lookup <host>: no such host
```

That message means "not on a runner whose VNet is linked to the zone", not "the
server is gone".

### Open verification: a real Azure server

The ownership model itself is proven: on PostgreSQL 16 the connecting admin is
granted every managed role (`postgresql_grant_role`) before databases are
owned by the `<deployment>` app role. That is shown against `postgres:16` as a
CREATEROLE non-superuser, both for a server this stack creates and for one it
consumes. **Still unverified:** a real `tofu plan`/apply against a
representative Azure Database for PostgreSQL Flexible Server, whose admin role
(`azure_pg_admin`) has its own privileges. Any fix belongs in this stack's
Azure wiring, not in a harness.

## Extension claims

`var.extensions` is a map keyed by a consumer-chosen extension id; each value
may carry any subset of a **closed set** of three claim kinds — `object_buckets` (a storage account each),
`managed_databases` (a database + optional owner role on the resolved server),
`dns_records` (merged into the zone; requires `enable_dns`). See
[`../../../docs/extensions.md`](../../../docs/extensions.md).

## Apply order on a greenfield cluster (read this)

Three providers are configured from facts that do not exist before the first
apply, so a fresh deployment is applied in **phases**:

```sh
# Phase 1 — cloud infra. The cluster's endpoint/certs and the Postgres server
# must exist before the kubernetes/helm/postgresql providers can connect.
terraform apply -target=module.cluster -target=module.postgres \
                -target=module.dns -target=module.blob -target=module.secrets_backend

# Phase 2 — everything in-cluster (RWX class, namespaces, gateway edge, roles).
terraform apply

# Phase 3 — once the Helm bring-up has Keycloak answering at keycloak_url:
terraform apply   # with enable_identity_realm = true
```

**Reachability of the Postgres server.** With the default
`postgres_network_access = "private"` the server answers only inside the VNet,
and the `postgresql` provider (roles, grants, extension owners) runs where
`terraform apply` runs. Apply from a VPN/bastion/runner inside the VNet, or use
`"public"` with explicit `postgres_public_firewall_rules`. Nothing here
guesses which.

**Consume mode does not hit the cluster caveat.** With `enable_cluster = false`
the cluster is **read** by name, so its facts are known before the providers
configure. The import path does not hit it either — see
[`../../../docs/import-runbook.md`](../../../docs/import-runbook.md).

## Azure specifics worth knowing

- AKS hands out client-certificate kubeconfigs, so the `kubernetes`/`helm`
  providers use cert + key (no token). Local accounts stay enabled for that.
- The RWX class is `nfs-rwx-storage` on every cloud — a consumer references
  one name — but here it is backed by the AKS-built-in Azure Files CSI driver
  (`file.csi.azure.com`, Premium NFS by default); no provisioner chart is
  managed.
- Postgres roles are created through the `cyrilgdn/postgresql` provider,
  configured from values the stack decides (derived host, minted admin
  password — or, in consume mode, the password read from Key Vault) rather
  than module outputs — a provider fed by the outputs of the
  module that uses it is a cycle.
- `ca_certificate` for Postgres is `""` because the chain is anchored on public
  roots; `sslmode=verify-full` works with the OS bundle.

## Usage

This stack is consumed by a root such as [`examples/azure`](../../../examples/azure).
Reusable stacks carry no `backend {}` block — the consuming root owns the backend.
See [`../../../docs/CONVENTIONS.md`](../../../docs/CONVENTIONS.md) for state & secret rules.
