# stacks/azure/xema-substrate

Composes the full Xema substrate on Azure from the per-cloud primitives and the cloud-agnostic addons: AKS, PostgreSQL Flexible Server, DNS, blob storage, Key Vault with External Secrets, optional Redis and container registry, ReadWriteMany storage, namespaces, the Gateway and TLS edge, and the Keycloak realm.

Every name is derived from one input, `deployment_name`. The stack names no service or application.

## When to use it

Use it to stand up (or, in consume mode, extend) a deployment's substrate on Azure. Consume it from a root such as [`examples/azure`](../../../examples/azure); the root owns the backend and provider credentials. Azure authentication is the provider's own chain (`az login`, `ARM_*`, managed identity, OIDC).

## Usage

Apply in this order:

| Step | What | Run from |
| --- | --- | --- |
| 0 | [`providers/azure/state-bucket`](../../../modules/providers/azure/state-bucket), once | anywhere |
| 1 | [`stacks/azure/xema-foundation`](../xema-foundation) (network, private DNS zones, management runner) | anywhere |
| 2 | this stack | the management runner |

Pass the foundation's `network` output unchanged to this stack's `network` input, and add the runner's public IP to `cluster_authorized_ip_ranges`.

On a fresh cluster, apply in phases, because the `kubernetes`, `helm` and `postgresql` providers connect to resources this stack creates:

```sh
terraform apply -target=module.cluster -target=module.postgres \
                -target=module.dns -target=module.blob -target=module.secrets_backend
terraform apply                       # in-cluster resources and roles
terraform apply                       # again with enable_identity_realm = true, once Keycloak answers at keycloak_url
```

The External Secrets identities need no Kubernetes: `-target=module.external_secrets[0].azurerm_role_assignment.store` (the identities come with it) and `...azurerm_federated_identity_credential.store` can join the first phase.

With the default `postgres_network_access = "private"`, apply from inside the VNet (the runner), or use `"public"` with `postgres_public_firewall_rules`. Consume mode and the import path ([`docs/import-runbook.md`](../../../docs/import-runbook.md)) skip the phases.

## Derived names

For `deployment_name = "acme-dev"` (3-20 characters, lowercase, single hyphens):

| Resource | Name |
| --- | --- |
| resource group, cluster | `acme-dev-rg`, `acme-dev-aks` |
| Postgres server, operator vault, Redis | `acme-dev-pg`, `acme-dev-kv`, `acme-dev-redis` |
| storage account | `acmedevblob` (hyphens removed) |
| Keycloak realm, blob container prefix | `acme-dev` |
| databases | `acme_dev_<name>` for each name in `platform_databases` |
| roles | `acme_dev` (app), `acme_dev_provisioner` (CREATEDB; omitted with `postgres_provisioner_role = "disabled"`) |
| namespaces | not derived; `workload_namespaces` is passed by full name |

`environment` (`dev` or `prod`) decides irreversible settings, such as the backup retention window. Four names are unique across all Azure tenants and can be overridden when taken: `operator_vault_name`, `storage_account_name`, `postgres_server_name`, `redis_cache_name` (and `secret_store_boundaries.<b>.vault_name` for boundary vaults).

## Configuration

Main inputs. All are in [`variables.tf`](variables.tf).

| Input | Required | Description |
| --- | --- | --- |
| `deployment_name` | yes | derives every name |
| `environment` | yes | `dev` or `prod` |
| `region`, `apex_domain` | yes | Azure location and DNS zone |
| `network` | when the stack creates anything in the VNet | the foundation's `network` output |
| `platform_databases` | yes | unprefixed logical database names; each becomes `<deployment_name as _>_<name>` |
| `workload_namespaces` | yes | full namespace names (DNS-1123) |
| `enable_cluster`, `enable_managed_postgres`, `enable_dns`, `enable_object_storage`, `enable_secrets_backend`, `enable_rwx_storage`, `enable_workload_namespaces`, `enable_gateway_tls`, `enable_identity_realm` | no (default `true`) | gate each area; a disabled area is consumed, never destroyed |
| `enable_cache`, `enable_container_registry`, `enable_deployer_identity` | no (default `false`) | optional areas |
| `cluster_name`, `cluster_resource_group_name` | consume mode | the existing cluster to read |
| `kubernetes_version`, `node_pools`, `default_pool_id`, `cluster_authorized_ip_ranges`, `cluster_network_policy_engine` | no | cluster shape |
| `cluster_automatic_upgrade_channel`, `cluster_node_os_upgrade_channel`, `cluster_maintenance_window_auto_upgrade`, `cluster_maintenance_window_node_os` | no | AKS upgrade channels and windows; null is Azure's default |
| `cluster_private` | no | `{ public_fqdn, private_dns_zone }`: a private API. `private_dns_zone = "None"` with `public_fqdn = true` is the fix for a network on custom DNS (nodes use the API's public name) |
| `cluster_dns_forward_zones` | no | zones CoreDNS forwards to Azure DNS (`coredns-custom` ConfigMap), so pods resolve private endpoints on a custom-DNS network; see [`coredns-custom`](../../../modules/cluster-addons/coredns-custom) |
| `postgres_engine_version`, `postgres_network_access`, `postgres_extensions`, `postgres_zone`, `postgres_provisioner_role` | no | database server shape; `postgres_zone` must be set before the first apply |
| `existing_postgres_server_id`, `existing_postgres_host`, `existing_postgres_admin_login`, `existing_postgres_admin_password_key_vault_id` | consume mode | the existing server |
| `backing_services_network_access` | no | `private` (default) turns off public endpoints of cache, storage and vault and adds private endpoints |
| `secret_store_boundaries` | no | map of boundary name to `{ namespaces, vault_name? }`; each gets its own vault, identity and `SecretStore` |
| `key_vault_secrets` | no | sensitive; secrets seeded into the operator vault (pass via `TF_VAR_*`) |
| `gateway_listeners`, `acme_email`, `tls_solver`, `gateway_implementation`, `customer_gateway` | with `enable_gateway_tls` | one HTTPS listener per hostname; see [`gateway-tls`](../../../modules/cluster-addons/gateway-tls) |
| `cluster_issuer_name`, `secret_store_name` | no | in-cluster names (defaults `letsencrypt`, `platform`), returned as outputs of the same name |
| `external_secrets_chart_repository`, `external_secrets_chart_version`, `external_secrets_images` | no | Offline sources for the External Secrets Operator: chart repository (HTTPS or `oci://`), version, and per-image `{ repository, tag, digest }` (digest required). Null/empty keeps the module defaults. |
| `ngf_chart_repository`, `ngf_chart_version`, `ngf_images` | no | The same for NGINX Gateway Fabric (images `controller`, `nginx`). |
| `cert_manager_chart_repository`, `cert_manager_chart_version`, `cert_manager_images` | no | The same for cert-manager (images `controller`, `webhook`, `cainjector`, `acmesolver`, `startupapicheck`). |
| `keycloak_url`, `keycloak_client_id`, `keycloak_client_secret` | with `enable_identity_realm` | Keycloak connection |
| `realm_clients`, `realm_roles`, `realm_protocol_mappers` | no | leave empty when your identity service reconciles them on boot |
| `extensions` | no | claims for dedicated resources: `object_buckets`, `managed_databases`, `dns_records` (see [`docs/extensions.md`](../../../docs/extensions.md)) |

A consumer root must also declare `platform_databases` and `workload_namespaces` as its own variables and pass them into the module call; [`examples/customer`](../../../examples/customer) shows the shape.

## Secret boundaries and the operator vault

Each `secret_store_boundaries` entry gets its own Key Vault (RBAC, purge protection, public access off) with a private endpoint, and `cluster-addons/external-secrets` creates the per-namespace identities and `SecretStore`s. A namespace may belong to one boundary only.

The operator vault holds break-glass and infrastructure secrets (`key_vault_secrets`, the created Postgres admin password). It is never projected into the cluster, has no identity or `SecretStore`, and only the principal running Terraform can write to it. Because every vault is private, run Terraform from inside the foundation's network.

## Consume mode

With `enable_managed_postgres = false`, the stack ensures the databases and roles inside the existing server over SQL, as `existing_postgres_admin_login`. It reads the admin password from Key Vault (`existing_postgres_admin_password_key_vault_id`, secret `postgres_admin_password_secret_name`, default `postgres-admin-password`), which an instance that created the server wrote to its operator vault. Run it where `existing_postgres_host` resolves (an in-VNet runner linked to the server's private DNS zone); otherwise apply stops with `no such host`.

With `enable_cluster = false` the cluster is read by name, so a single `terraform apply` is enough.

## Outputs

The `substrate` output is a non-secret map with the same keys on every cloud, described in [`docs/CONTRACTS.md`](../../../docs/CONTRACTS.md#binding-contract). A key is `null` when its area is disabled or consumed. Credentials are separate sensitive outputs (`postgres_uri`, `postgres_role_passwords`, `blob_primary_access_key`, `redis_primary_key`, `realm_client_secrets`, `kubeconfig_raw`). Other outputs include `gateway_parent_refs`, `secret_stores`, `operator_vault_id`, `cluster_issuer_name` and `secret_store_name`. Reference the operator vault by `operator_vault_id`.

Details: [`docs/CONVENTIONS.md`](../../../docs/CONVENTIONS.md), [`docs/CONTRACTS.md`](../../../docs/CONTRACTS.md).
