# `xema-substrate` stack — Azure

Composes the full Xema substrate on Azure from the per-cloud primitives and the
cloud-agnostic addons. **Every name is derived from one input,
`deployment_name`** (see [Derived names](#derived-names)); nothing in this stack
names a deployment.

| Module | What it provisions |
| --- | --- |
| `module.cluster` | AKS cluster + node pools + VNet (AKS subnet, Postgres-delegated subnet), workload identity on |
| `module.postgres` | PostgreSQL Flexible Server + the derived databases and roles |
| `module.dns` | the `apex_domain` zone's records (+ the cert-manager DNS-01 identity when that solver is used) |
| `module.blob` | the storage account the platform's blob adapter targets |
| `module.secrets_backend` | Key Vault + the External Secrets reader identity |
| `module.cache` | (optional, off by default) Azure Cache for Redis |
| `module.rwx_storage` | a ReadWriteMany `StorageClass` over the built-in Azure Files CSI driver (NFS) |
| `module.workload_namespaces` | the derived namespaces the Helm app bring-up expects |
| `module.ingress_tls` | ingress-nginx + cert-manager/ClusterIssuer + External Secrets/ClusterSecretStore |
| `module.identity_realm` | the Keycloak realm **container** (+ optional base clients/roles/mappers) |
| `module.extension_bucket` | dedicated storage accounts claimed by biomes (see below) |

> **Realm boundary:** when a platform app (e.g. `identity-api`) reconciles the
> realm's platform clients/roles/scopes/mappers on boot, leave `realm_clients` /
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
| namespaces | `acme-dev`, `acme-dev-shared`, `acme-dev-infra`, `acme-dev-opencode-workers`, `acme-dev-biome-sidecars` | verbatim + suffix |
| databases | `acme_dev_identity_api`, `acme_dev_secrets_api`, `acme_dev_event_hub_api`, `acme_dev_llm_gateway_api`, `acme_dev_mcp_gateway_api`, `acme_dev_org_database_pool_api`, `acme_dev_redis_pool_api`, `acme_dev_biomes`, `acme_dev_openfga`, `acme_dev_temporal`, `acme_dev_temporal_visibility`, `acme_dev_gitea`, `acme_dev_keycloak` (+ `acme_dev_billing_api` with `enable_billing_database`) | `-` → `_` (Postgres identifiers) |
| roles | `acme_dev` (app), `acme_dev_provisioner` (CREATEDB) | `-` → `_` |

`deployment_name` is validated (3-20 chars, lowercase, single hyphens) so every
derived name fits its Azure limit; the hyphen-to-underscore mapping for Postgres
is the one rewrite, and it is injective on that alphabet. `environment`
(`dev | prod`) decides the irreversible knobs: Key Vault purge protection and
the backup retention window are `prod`-only.

## The `substrate` output

One non-secret map the Helm layer consumes: `postgres_host` / `postgres_port` /
the role and database names, `blob_account` / `blob_endpoint` /
`blob_container_prefix`, `key_vault_uri` + the External Secrets client id and
`cluster_secret_store_name`, `redis_host` / `redis_port`, `dns_zone` +
`dns_name_servers`, an `ingress` hint (service name, namespace, class, issuer),
`keycloak_url` + `realm_name`, `oidc_issuer_url`, `storage_class_name`, the
namespaces. Credentials are the separate **sensitive** outputs
(`postgres_uri`, `postgres_role_passwords`, `blob_primary_access_key`,
`redis_primary_key`, `realm_client_secrets`, `kubeconfig_raw`), on purpose.

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
| `enable_workload_namespaces` | `true` | Ensure the derived namespaces exist. |
| `enable_ingress_tls` | `true` | Install the ingress edge (needs `acme_email`). |
| `enable_identity_realm` | `true` | Manage the Keycloak realm (needs a reachable `keycloak_url`). |

A disabled cloud module is `count`-gated to zero — the stack **consumes** the
existing resource instead of creating it; it never plans a destroy. When
`enable_cluster = false` but `enable_managed_postgres = true` with private
access, supply `existing_vnet_id` + `existing_delegated_subnet_id`.

## Extension / biome claims

`var.extensions` is a map keyed by biome id; each value may carry any subset of a
**closed set** of three claim kinds — `object_buckets` (a storage account each),
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
- The RWX class is `nfs-rwx-storage` on every cloud — the Helm layer references
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
