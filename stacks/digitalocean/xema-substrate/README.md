# stacks/digitalocean/xema-substrate

Composes the Xema substrate on DigitalOcean from the per-cloud primitives and the cloud-agnostic addons: a DOKS cluster, managed Postgres, DNS, ReadWriteMany storage, namespaces, the Keycloak realm and extension claims.

## When to use it

Use it to stand up (or, in consume mode, extend) a substrate on DigitalOcean. Consume it from a root such as [`examples/digitalocean`](../../../examples/digitalocean); the root owns the backend.

## Usage

Greenfield (all `enable_*` default to `true`): the `kubernetes` and `helm` providers are configured from the cluster's outputs, so apply in two phases.

```sh
terraform apply -target=module.cluster
terraform apply
```

Consume: set `enable_cluster`, `enable_managed_postgres` and `enable_dns` to `false` when another Terraform owns them. The stack then manages only RWX storage, namespaces, the realm and extension claims, reading the existing cluster by `cluster_name`, and extension databases land on `existing_database_cluster_id`. One `terraform apply` is enough. The import path ([`docs/import-runbook.md`](../../../docs/import-runbook.md)) also needs no phases.

`platform_databases` (verbatim names; `[]` when consuming a shared cluster) and `workload_namespaces` (full names) are required with no default.

When your identity service reconciles the realm's clients, roles and mappers on boot, leave `realm_clients`, `realm_roles` and `realm_protocol_mappers` empty.

## Extension claims

`extensions` is a map keyed by an extension id. Each value may carry `object_buckets`, `managed_databases` and `dns_records`. `managed_databases` land on the created Postgres cluster or on `existing_database_cluster_id`; `dns_records` need `enable_dns`. See [`docs/extensions.md`](../../../docs/extensions.md).

## Outputs

The `substrate` output is a non-secret map with the same keys as the Azure stack, described in [`docs/CONTRACTS.md`](../../../docs/CONTRACTS.md#binding-contract). Keys this stack does not model are `null`. Credentials are separate sensitive outputs (`postgres_uri`, `realm_client_secrets`, `kubeconfig_raw`).

## Configuration

| Input | Required | Description |
| --- | --- | --- |
| `enable_cluster` | no | Create the DOKS cluster. |
| `enable_managed_postgres` | no | Create the managed Postgres cluster. |
| `enable_dns` | no | Manage the DNS zone + records in this cloud. |
| `enable_rwx_storage` | no | Install the ReadWriteMany StorageClass + NFS provisioner on the (created or existing) cluster. |
| `enable_workload_namespaces` | no | Ensure the workload namespaces exist on the (created or existing) cluster. |
| `enable_identity_realm` | no | Manage the Keycloak realm (realm + clients + roles + mappers). |
| `do_token` | yes | DigitalOcean API token used to manage/read the cluster, database, DNS, and Spaces buckets. |
| `do_spaces_access_id` | no | DigitalOcean Spaces access key id (S3-compatible). |
| `do_spaces_secret_key` | no | DigitalOcean Spaces secret key (S3-compatible). |
| `keycloak_url` | no | Base URL of the Keycloak server (e.g, "https://id.example.com"). |
| `keycloak_client_id` | no | Keycloak admin client id for the client-credentials grant. |
| `keycloak_client_secret` | no | Keycloak admin client secret for the client-credentials grant. |
| `keycloak_admin_realm` | no | Realm the admin client authenticates against (typically "master"). |
| `region` | yes | DigitalOcean region slug shared by the cluster, database, and buckets (e.g, "fra1"). |
| `tags` | no | Tags applied to created cloud resources (cluster, database), keyed by tag name. |
| `cluster_name` | no | DOKS cluster name. |
| `kubernetes_version` | no | DOKS control-plane version slug prefix (e.g, "1.31."). |
| `node_pools` | no | Node pools keyed by a stable pool id (used only when enable_cluster). |
| `default_pool_id` | no | Which key in node_pools is the DOKS default pool (used only when enable_cluster). |
| `vpc_id` | no | Existing VPC uuid for a created cluster/database. |
| `cluster_auto_upgrade` | no | Enable DOKS patch auto-upgrade (created cluster only). |
| `cluster_surge_upgrade` | no | Enable DOKS surge upgrades (created cluster only). |
| `postgres_name` | no | Managed Postgres cluster name (created cluster only). |
| `postgres_engine_version` | no | Major Postgres version, e.g, "16" (created cluster only). |
| `postgres_size` | no | DO managed-database size slug, e.g, "db-s-1vcpu-2gb" (created cluster only). |
| `postgres_node_count` | no | Postgres node count (1 = single node, 2+ = primary plus standby replicas). |
| `platform_databases` | yes | The logical databases to ensure on the CREATED cluster, by name, used verbatim. |
| `postgres_roles` | no | Base logical roles on the CREATED cluster. |
| `existing_database_cluster_id` | no | Provider id of an existing managed-Postgres cluster to host extension-claimed dedicated databases when enab... |
| `dns_domain` | no | Managed DNS zone apex, e.g, "example.com" (used only when enable_dns). |
| `dns_records` | no | Base DNS records keyed by a stable id (used only when enable_dns). |
| `rwx_storage_class_name` | no | Name of the ReadWriteMany StorageClass to create. |
| `rwx_chart_version` | no | Pinned Helm chart version for the NFS provisioner. |
| `rwx_is_default_class` | no | Mark the RWX StorageClass as the cluster default. |
| `rwx_manage_provisioner_chart` | no | Install/manage the NFS provisioner Helm release. |
| `rwx_storage_provisioner` | no | The provisioner field on the RWX StorageClass (must match the installed provisioner). |
| `rwx_allow_volume_expansion` | no | Whether PVCs bound to the RWX StorageClass may be expanded (match the live class when importing). |
| `workload_namespaces` | yes | The roster of namespaces to ensure exist on the (created or consumed) cluster, by full name. |
| `workload_namespace_labels` | no | Optional per-namespace labels, keyed by namespace name. |
| `realm_name` | no | The single Keycloak realm this stack owns (e.g, "acme-prod"). |
| `realm_display_name` | no | Human-readable realm display name shown on login screens. |
| `realm_access_token_lifespan` | no | Access-token lifespan for the managed realm, as a Go duration string (e.g, "5m"). |
| `realm_clients` | no | OpenID clients to create in the realm, keyed by a stable id. |
| `realm_roles` | no | Realm-level roles to create. |
| `realm_protocol_mappers` | no | Per-client user-attribute → token-claim protocol mappers, keyed by a stable id. |
| `extensions` | no | Dedicated substrate claimed by extensions — consumers of this substrate that need a cloud resource of their... |
| `enable_deployer_identity` | no | Manage the deployment's namespaces, its least-privileged deployer ServiceAccount, that account's token, and... |
| `deployer_deployment_name` | no | The deployment this identity belongs to. |
| `deployer_namespace` | no | The namespace the deployment's workloads run in — the one its own descriptor DECLARES. |
| `deployer_additional_namespaces` | no | Every OTHER namespace the same identity deploys into — typically the deployment's infrastructure namespace. |
| `deployer_service_account_name` | no | Name of the deployer ServiceAccount, its Role and its RoleBindings. |
| `deployer_manage_namespaces` | no | Create the deployer's namespaces here. |
| `deployer_context_name` | no | The alias written into the emitted kubeconfig's context/cluster/user. |

Outputs: `cluster_id`, `cluster_endpoint`, `kubeconfig_raw`, `vpc_id`, `postgres_host`, `postgres_port`, `postgres_uri`, `dns_domain`, `dns_record_ids`, `storage_class_name`, `workload_namespaces`, `postgres_databases`, `realm_id`, `realm_client_secrets`, `extension_buckets`, `extension_databases`, `deployer_kubeconfig`, `substrate`.
