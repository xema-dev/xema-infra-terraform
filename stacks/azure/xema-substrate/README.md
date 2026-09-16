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
| `module.dns` | the `apex_domain` zone's records (+ the cert-manager DNS-01 identity when that solver is used) |
| `module.blob` | the storage account the platform's blob adapter targets |
| `module.secrets_backend` | Key Vault + the External Secrets reader identity |
| `module.cache` | (optional, off by default) Azure Cache for Redis |
| `module.rwx_storage` | a ReadWriteMany `StorageClass` over the built-in Azure Files CSI driver (NFS) |
| `module.workload_namespaces` | the `workload_namespaces` roster the consumer supplies |
| `module.ingress_tls` | ingress-nginx + cert-manager/ClusterIssuer + External Secrets/ClusterSecretStore |
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
| `platform_databases` | the logical databases to ensure on the created server, UNPREFIXED (`"identity"`, `"billing"`, …) | each becomes `<deployment_name as _>_<name>`; validated `^[a-z][a-z0-9_]{0,42}$`; ignored when `enable_managed_postgres = false` |
| `workload_namespaces` | the namespaces to ensure exist, by FULL name | DNS-1123 labels; nothing is derived from `deployment_name`; ignored when `enable_workload_namespaces = false` |

Both have **no default**: which databases and namespaces a deployment needs is
a fact about what it deploys, derived by the consumer from its own
distribution, and a stack invoked without them refuses to plan. There is no
per-database switch — a database exists because it is in the list. A consumer
that wants `<deployment_name>-<role>` namespaces spells that out itself.

**A consumer ROOT must DECLARE them and pass them into the module call.** A
`*.tfvars` / `*.auto.tfvars.json` sets variables of the ROOT, not of this
stack: a root that declares no `variable "platform_databases"` and does not
write `platform_databases = var.platform_databases` in its `module
"substrate"` block fails with `The argument "platform_databases" is required`
however complete its tfvars is. The same holds for `workload_namespaces` and
every other required input. `examples/customer/` is the shape — every
required input declared in the root's `variables.tf` and passed through.

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
(default `platform`) are threaded to the `ingress-tls` addon, validated as
DNS-1123 subdomain names, and **read back** as the stack outputs of the same
name (and in the `substrate` map: `substrate.ingress.cluster_issuer_name`,
`substrate.cluster_secret_store_name`). A consumer's `Ingress`
(`cert-manager.io/cluster-issuer`) and `ExternalSecret` (`secretStoreRef.name`)
manifests should read them from the stack, never restate the defaults. Both
outputs are `null` exactly when the object does not exist — `enable_ingress_tls
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

## Two modes — greenfield vs consume

Every area is **independently toggleable** via an `enable_*` input:

| Input | Default | What it gates |
| --- | --- | --- |
| `enable_cluster` | `true` | Create AKS + VNet. `false` ⇒ read the existing cluster by `cluster_name` / `cluster_resource_group_name`. |
| `enable_managed_postgres` | `true` | Create the Flexible Server. `false` ⇒ extension databases target `existing_postgres_server_id` (+ `existing_postgres_host` and admin creds for owner roles). |
| `enable_dns` | `true` | Manage the `apex_domain` zone. `false` ⇒ DNS owned elsewhere (extension `dns_records` and `dns01-azure` then fail fast). |
| `enable_object_storage` | `true` | Create the blob storage account. |
| `enable_secrets_backend` | `true` | Create the Key Vault + reader identity (and the External Secrets store when `enable_ingress_tls`). |
| `enable_cache` | `false` | Create a managed Redis. Off: the platform runs valkey in-cluster. |
| `enable_rwx_storage` | `true` | Create the RWX `StorageClass` on the (created or consumed) cluster. |
| `enable_workload_namespaces` | `true` | Ensure the `workload_namespaces` roster exists. |
| `enable_ingress_tls` | `true` | Install the ingress edge (needs `acme_email`). |
| `enable_identity_realm` | `true` | Manage the Keycloak realm (needs a reachable `keycloak_url`). |

A disabled cloud module is `count`-gated to zero — the stack **consumes** the
existing resource instead of creating it; it never plans a destroy. When
`enable_cluster = false` but `enable_managed_postgres = true` with private
access, supply `existing_vnet_id` + `existing_delegated_subnet_id`.

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

# Phase 2 — everything in-cluster (RWX class, namespaces, ingress edge, roles).
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
  password) rather than module outputs — a provider fed by the outputs of the
  module that uses it is a cycle.
- `ca_certificate` for Postgres is `""` because the chain is anchored on public
  roots; `sslmode=verify-full` works with the OS bundle.

## Usage

This stack is consumed by a root such as [`examples/azure`](../../../examples/azure).
Reusable stacks carry no `backend {}` block — the consuming root owns the backend.
See [`../../../docs/CONVENTIONS.md`](../../../docs/CONVENTIONS.md) for state & secret rules.
