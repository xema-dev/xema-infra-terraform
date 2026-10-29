# Changelog

Consumers pin this module set by `?ref=vX.Y.Z`. Every entry below names what a
consumer root on the PREVIOUS tag must change to adopt the release — not what
was committed, but what a `main.tf` + tfvars have to say differently.

## Unreleased — Azure-managed upgrades, ESO identities independent of Kubernetes (XEMA-3782)

Needs a change in a root that sets `kubernetes_version` to a value other than the cluster's current minor, or passes `automatic_upgrade_channel = ""`. Otherwise a root plans no change except one new built-in `terraform_data.namespaces_ready` (creates nothing). No resource address moves; no state migration.
**Module `providers/azure/cluster`:**
- `kubernetes_version` reaches the cluster as given (a minor alias such as `"1.34"`, or a full version) and is no longer ignored after create, nor is the default pool's `orchestrator_version`: a bump is a real upgrade. Set it to the cluster's current minor before the first plan, or the plan tries to move the cluster to that version. The `azurerm_kubernetes_service_versions` lookup is gone.
- `automatic_upgrade_channel` defaults to `null` (Azure's default, no automatic upgrade) and no longer accepts `""`; it also accepts `"none"`. New: `node_os_upgrade_channel` (`null` = Azure's NodeImage), `maintenance_window_auto_upgrade` and `maintenance_window_node_os` (default `null`, no window). Rules live in the provider-free `providers/azure/cluster-upgrades` submodule, with tests.
- `upgrade_settings` of the default pool and of extra pools is in `ignore_changes`: azurerm reads Azure's 10% default into state and sends nil, so every apply planned a cluster update.
**Module `cluster-addons/external-secrets`:** new `namespaces_ready` (any, default `null`). Only the `helm_release.secret_store` releases wait for it; the identities, federated credentials and role assignments depend on nothing in Kubernetes. **Stack `stacks/azure/xema-substrate`:** the module-level `depends_on = [module.workload_namespaces]` is replaced by `namespaces_ready`; new `cluster_automatic_upgrade_channel`, `cluster_node_os_upgrade_channel`, `cluster_maintenance_window_auto_upgrade`, `cluster_maintenance_window_node_os`.
**Module `providers/azure/secrets-backend`:** `soft_delete_retention_days` defaults to `null` (Azure's 90 days) for new vaults; an existing vault keeps its value (the field is in `ignore_changes`, since Azure cannot update it).

## v0.19.0 — private DNS for AKS on custom-DNS networks (HAM-5)

Additive; nothing to change to adopt. A root that leaves the new inputs unset plans no change.
**Module `providers/azure/cluster`:** new `private_dns_zone_id` (null, `"System"`, `"None"` or a private DNS zone resource id; default null keeps the AKS default). `"None"` needs `private_cluster_enabled` and `private_cluster_public_fqdn_enabled`: the nodes then use the API's public name, whose public record holds the private IP. A network on custom DNS otherwise fails node bootstrap with `VMExtensionError_K8SAPIServerDNSLookupFail` (NXDOMAIN for `<name>.privatelink.<region>.azmk8s.io`), even with the public FQDN enabled. The rules are in the provider-free `providers/azure/private-dns-zone` helper, with tests.
**Stack `stacks/azure/xema-substrate`:** `cluster_private` gains `private_dns_zone` (optional string), passed to `private_dns_zone_id`.
**Module `cluster-addons/coredns-custom` (new), stack `cluster_dns_forward_zones`:** a list of DNS zones (default `[]`, creates nothing). A `coredns-custom` ConfigMap in `kube-system` gives CoreDNS one server block per zone, forwarding to Azure DNS (`168.63.129.16`), so pods resolve private endpoints (`privatelink.vaultcore.azure.net`, `privatelink.postgres.database.azure.com`, `privatelink.blob.core.windows.net`) when the network's own DNS cannot. Each zone must be linked to the cluster's network. Rendering and zone rules are in the provider-free `server-blocks` submodule, with tests.

## v0.18.0 — overridable chart and image sources for offline registries (HAM-80)

Additive; nothing to change to adopt. A root that leaves the new inputs unset plans no change: the defaults are the repositories and versions that were hard-coded, and no values are added.
**Module `cluster-addons/external-secrets`:** `chart_repository` (default `https://charts.external-secrets.io`) and `images` (map keyed `controller`, `webhook`, `cert_controller` of `{ repository, tag, digest }`, default `{}`).
**Module `cluster-addons/gateway-tls`:** `ngf_chart_repository` (default `oci://ghcr.io/nginx/charts`), `ngf_images` (keys `controller`, `nginx`), `cert_manager_chart_repository` (default `https://charts.jetstack.io`), `cert_manager_images` (keys `controller`, `webhook`, `cainjector`, `acmesolver`, `startupapicheck`).
The chart repository may be an `oci://` path. Every image entry needs a `sha256:<64 hex>` digest and a tag: a tags-only override is refused at plan. cert-manager renders the chart's `digest` key; External Secrets and NGINX Gateway Fabric have no digest key, so the module sets the tag value to `<tag>@<digest>` (the charts render `repository:tag`).
**Stack `stacks/azure/xema-substrate`:** pass-through `external_secrets_*`, `ngf_*` and `cert_manager_*` (`chart_repository`, `chart_version`, `images`); null/empty keeps the module defaults. The chart-version inputs (`chart_version`, `ngf_chart_version`, `cert_manager_chart_version`) are now `nullable = false`: an explicit `null` means the pinned default, not the latest chart. The image rules and the values they render to live in provider-free `images-plan` submodules with tests. `rwx-storage` is unchanged (its chart is caller-chosen; use `chart_values`).

## Unreleased — private CA trust on AKS nodes (Azure)

Additive; nothing to change to adopt. A root that leaves the new inputs unset plans no change. The `azurerm >= 5.0` floor is unchanged, because 5.0.0 already has the field.
**Module `providers/azure/cluster`:** new `custom_ca_trust_certificates = list(string)`, default `[]`. It holds PEM CA certificates, which are added to every
Linux node's OS trust store through AKS custom CA trust (`custom_ca_trust_certificates_base64`). Pods do not see them. Each entry holds one certificate, and the list holds at most 10.
Changing the set replaces every node, one at a time. The node-pool `custom_ca_trust_enabled` flag is not used: AKS retired it, and azurerm 5.x removed it.
Refused at plan (provider-free, `providers/azure/node-ca-trust/tests`): more than 10 certificates, more than 35000 bytes of PEM content in total, or an entry that is not
exactly one LF-terminated PEM certificate (a bundle, a key, CRLF).
**Security:** A CA in the node OS trust store is trusted for every TLS name the node reaches: container registries, public image hosts, and the control plane through the kubelet. Whoever holds its private key can intercept any of that traffic on every node. Use a CA created only for this purpose and name-constrained to what the nodes must trust: X.509 `nameConstraints` with a permitted DNS subtree, or an IP range, that covers only the private registry or endpoint.
The 35 KB limit is the one AKS documents for the PEM certificate content (https://learn.microsoft.com/azure/aks/custom-certificate-authority), counted as 35000 bytes with entries joined by a blank line.
**Stack `stacks/azure/xema-substrate`:** pass-through input `cluster_custom_ca_trust_certificates`, default `[]`.

## Unreleased — identity-api owns all realm policy; identity-realm keeps only the shell (BREAKING for module consumers)

BREAKING, no shim. `modules/identity-realm` keeps only the realm shell (`realm_name`, `enabled`, `display_name`) and its
clients/roles/mappers. The inputs `access_token_lifespan`, `login_with_email_allowed`, `registration_allowed`, `reset_password_allowed`,
`ssl_required`, `sso_session_idle_timeout` and `sso_session_max_lifespan` are removed, and the `keycloak_realm` ignores those attributes (`lifecycle.ignore_changes`). identity-api is the single owner of realm policy: it
reconciles seven settings at boot, holding the realm at the default when a key is unset: `accessTokenLifespanSeconds` (default 300), `loginWithEmailAllowed` (true), `registrationAllowed` (false), `resetPasswordAllowed` (true), `sslRequired` (`external`), `ssoSessionIdleTimeoutSeconds` (1800) and `ssoSessionMaxLifespanSeconds` (36000). They are set in identity-api's configuration at `REALM_POLICIES.<realm>.realmSettings.<key>`. The values are integer seconds, not Go durations (`5m` is `300`). Minimum version: the first identity-api release that contains develop commit c31d929e. The pass-through
variable `realm_access_token_lifespan` is removed from `stacks/digitalocean/xema-substrate`, `stacks/azure/xema-substrate` and
`examples/customer`. A consumer root must delete `realm_access_token_lifespan` (and any of the removed inputs passed to the module) from its `main.tf` and tfvars, and set the values in identity-api's configuration
instead. Terraform no longer plans a change for any of these settings.

## Unreleased — one Gateway, many hosts and apex domains, a certificate per listener (BREAKING)

BREAKING, no shim. **Module `cluster-addons/gateway-tls`:** `gateway_hostname` and `gateway_tls_secret_name` are gone; the new
`listeners = map(object({ hostname, certificate_mode, secret_name = optional }))` declares one HTTPS listener per hostname, keyed by
listener name (the HTTPRoute `sectionName`), each with its own certificate. `certificate_mode` is `managed` (the module renders a
cert-manager `Certificate` from the ClusterIssuer into `<gateway_name>-<key>-tls`; `secret_name` refused) or `customer_supplied`
(`secret_name` required: the customer's `kubernetes.io/tls` Secret in `gateway_namespace`; nothing issued). The Gateway no longer
carries `cert-manager.io/cluster-issuer` (the gateway-shim issues nothing); the port-80 listener has no hostname and serves every
host. cert-manager and the ACME ClusterIssuer are installed only when something is issued (a managed listener, or a
customer-managed Gateway): `acme_email` and `tls_solver` default to `null`, are required exactly then and refused otherwise, and the
output `cluster_issuer_name` is `null` without an issuer. Refused at plan (provider-free, `gateway-tls/tls-plan/tests`): duplicate hostnames, a customer_supplied listener without a
valid secret, a managed one with one, an unknown mode, a managed wildcard with `http01`, a managed hostname outside the
`dns01-azure` zone, a customer Secret equal to a managed one, the reserved name `http`, more than 63 listeners. `customer_gateway`'s
`https_section_name` is `https_section_names` (a set; each a DNS-1123 label other than `http`, the rule listener keys follow). `dns01_azure.hosted_zone_name` is `hosted_zone_names` (a set): one DNS-01 solver per zone, selected by `dnsZones`, so each apex issues from its own zone. Output `gateway_parent_ref` is `gateway_parent_refs` (keyed by listener).
**Stack `stacks/azure/xema-substrate` / `examples/azure`:** `gateway_hostname` is `gateway_listeners` (same shape as `listeners`);
output `gateway_parent_ref` is `gateway_parent_refs`; `substrate.gateway.parent_ref` is `substrate.gateway.parent_refs`. `acme_email` and `tls_solver`
default to `null` (were `""` and `"http01"`): a root with a managed listener sets both; one with only customer_supplied listeners sets neither. A root that
set `gateway_hostname = "h"` sets `gateway_listeners = { <name> = { hostname = "h", certificate_mode = "managed" } }` and takes its
deployment's `gateway.parentRef` from `parent_refs["<name>"]` (`tooling/bind` prints the block for a named listener).

**Upgrading an existing `enable_gateway_tls` install** (nginx-gateway-fabric), in this order:

1. **Remove the old Certificate and Secret first, by hand.** The previous listener certificate was a `Certificate` named
   `gateway_tls_secret_name` (default `gateway-tls`) in `gateway_namespace`, created by cert-manager's gateway-shim from the
   Gateway's annotation — not by Terraform or Helm, so no plan destroys it. Removing the annotation does not delete it either (the
   shim only acts on annotated Gateways, and the Certificate is owned by the Gateway, which is kept), so it would keep renewing
   into that Secret — including over a customer_supplied Secret of the same name. Before applying, run
   `kubectl -n <gateway_namespace> delete certificate <gateway_tls_secret_name>` and then
   `kubectl -n <gateway_namespace> delete secret <gateway_tls_secret_name>`.
2. **Plan a window: HTTPS is down until ACME issues.** A managed listener's Secret is now `<gateway_name>-<key>-tls`, a new and empty
   Secret, so its host serves no valid certificate until cert-manager issues it (minutes with a healthy solver). A customer_supplied
   listener has no gap if its Secret exists in `gateway_namespace` before the apply.
3. **Keep the listener key `https`, or move the routes.** HTTPRoutes attached with `sectionName: https` detach unless the listener
   that serves their host keeps the key `https` (`gateway_listeners = { https = { hostname = "<old gateway_hostname>",
   certificate_mode = "managed" } }` keeps them attached). Any other key: update each deployment's `gateway.parentRef.sectionName`
   to it in the same window.

## Unreleased — bind classifies the substrate's kubelet/registry fields; root-local outputs declared by the root

No input or resource change; nothing to adopt except the BIND tool. `tooling/bind` now classifies `substrate.kubelet_identity_object_id`,
`substrate.container_registry_login_server`, `substrate.container_registry_id` (and the same top-level outputs) as not-a-binding, so a
root on `stacks/azure/xema-substrate` v0.16.0 no longer gets "unknown stack output(s)" for them. A consumer root's own outputs are
declared not-a-binding with a root output `xema_bind_root_local_outputs = ["name", ...]` (see `tooling/bind/README.md`), no edit to the
vendored table; names colliding with a stack output are refused. A test now fails here if any stack output or `substrate` field lacks a
disposition.

## v0.16.0 — a Key Vault per secret trust boundary, an operator vault, one identity per boundary namespace (BREAKING)

BREAKING, no shim; measured from v0.15.0.

**Stack `stacks/azure/xema-substrate`.** The single `secret_stores`-serving vault and its "at most one entry" limit are gone. New
input `secret_store_boundaries = map(object({ namespaces, vault_name = optional }))`, keyed by boundary name: for EACH boundary the
stack creates its own Key Vault (RBAC, purge protection on, public access off), its private endpoint in the foundation's
private-endpoint subnet and `vault` private DNS zone, and passes `{ namespaces, key_vault_id, vault_uri }` to
`cluster-addons/external-secrets`. Vault names derive as `<deployment_name>-<boundary>-kv`; a derived name outside 3-24
letters/digits/single hyphens (starting with a letter) is refused, never truncated: set that boundary's `vault_name`. The provider-free
`modules/providers/azure/vault-names` validates names and refuses duplicates, including a boundary equal to the operator vault.
Every boundary namespace must be in `workload_namespaces` (refused at plan, provider-free check in `external-secrets/boundaries`;
skipped when `enable_workload_namespaces = false`), and the add-on now waits for the namespaces, so a first apply on a fresh
cluster no longer fails with "namespace not found". New output `secret_store_name`, `secret_stores`; removed input `secret_stores`.

**Operator vault.** The remaining stack vault is the OPERATOR vault (break-glass/infra secrets, never projected into the cluster):
it holds `key_vault_secrets` and the created Postgres admin password, has no identity or SecretStore and is never given to the
add-on. Seeding it now waits for its private endpoint (explicit dependency). Renamed: input `key_vault_name` -> `operator_vault_name`;
outputs `key_vault_name`/`key_vault_id`/`key_vault_uri` -> `operator_vault_name`/`operator_vault_id`/`operator_vault_uri`;
`substrate.key_vault_*` -> `substrate.operator_vault_*`; `substrate.external_secrets_client_id` and
`substrate.cluster_secret_store_name` -> `substrate.secret_stores` and `substrate.secret_store_name`.

**Add-on `cluster-addons/external-secrets`.** No more cluster-wide `ClusterSecretStore/platform` (one vault, one identity, every
namespace). It takes `secret_stores = map(object({ namespaces, key_vault_id, vault_uri }))` keyed by boundary and creates, per
(boundary, namespace), ONE user-assigned managed identity `<deployment_name>-eso-<boundary>-<namespace>` (Azure refuses concurrent
federated-credential writes on one identity and caps 20 per identity) with a single federated credential for
`system:serviceaccount:<namespace>:secret-store`, `Key Vault Secrets User` on ONLY that boundary's vault, and a namespaced
`SecretStore` in the namespace using that identity. An identity name outside Azure's 3-128 limit or allowed characters is refused,
never truncated. No two boundaries may share a namespace or a vault. Required new inputs: `region`, `resource_group_name`,
`oidc_issuer_url`; removed: `cluster_secret_store_name`, `secret_store_backend`, `azure_key_vault_store`, `service_account_name`;
output `cluster_secret_store_name` -> `secret_store_name`. `modules/assigned-roles` gains an `external-secrets` entry (gated by
`enable_secrets_backend`; `Key Vault Secrets User`). `examples/azure` follows.

**Migration.**
- After the upgrade the old vault is the OPERATOR vault: unreadable by any cluster identity. ExternalSecrets stop syncing until the
  boundary vaults are seeded (by the consumer) and manifests switch to `secretStoreRef: { kind: SecretStore, name: platform }`.
- Purge protection is now ALWAYS on (it was prod-only). Enabling it on an existing dev vault is IRREVERSIBLE.
- Renaming a boundary destroys that boundary's vault (soft-deleted for 7 days; recreating the same name recovers the old secrets).
- A root with `backing_services_network_access = "public"` and no `network` now fails plan: the vaults are always private and need
  the foundation's `network` and `vault` private link zone.
- A `moved` block (`module.private_endpoint["vault"]` -> `module.operator_vault_private_endpoint[0]`) keeps a running operator vault's private endpoint instead of recreating it; drop it at v0.17.

### Also in this release: Azure substrate stack passes `network_policy_engine` through

No consumer change is required (patch-level). `stacks/azure/xema-substrate` gains `cluster_network_policy_engine`
(`"cilium"` default | `"calico"`), passed to `modules/providers/azure/cluster` as `network_policy_engine`, so a stack consumer
can select Calico. The closed list is validated by the cluster module's `network-policy-engine` submodule (an invalid value is
refused at plan). The default is unchanged. Changing it on an existing cluster recreates the cluster.

## v0.15.0 — AKS enforces NetworkPolicy by default

No consumer change is required to adopt it, but a consumer with an EXISTING AKS cluster gets a plan that RECREATES it: the
cluster now sets `network_data_plane = "cilium"` and `network_policy = "cilium"` (Azure CNI overlay with the Cilium
dataplane), because AKS with no policy engine silently ignored every NetworkPolicy. `modules/providers/azure/cluster` gains
`network_policy_engine` (`"cilium"` default | `"calico"`; no `"none"`). Land it before the first apply of a
new cluster; on a live one, choose a maintenance window.

## v0.14.5 — container registry sets the AzureServices network bypass explicitly

No consumer change is required. `modules/providers/azure/container-registry` now sets `network_rule_bypass_option =
"AzureServices"` instead of relying on the azurerm default (the value is unchanged, so no plan diff). `az acr import` into
the network-restricted registry works only with this bypass, and it is how a customer installation receives Xema images, the
engine image and the edition by exact digest.

## v0.14.3 — optional Postgres provisioner role (Azure substrate); BIND skips absent custody

No consumer change is required. `stacks/azure/xema-substrate` gains `postgres_provisioner_role` (`"enabled"` | `"disabled"`,
default `"enabled"`, i.e. today's behaviour). `"disabled"` skips the second `<deployment>_provisioner` role (CREATEDB), for a
consumer such as a Temporal server's database that never provisions databases at runtime: only the app role is created and
granted, the role is absent from the `postgres_roles` and `postgres_role_passwords` outputs, and
`substrate.postgres_provisioner_role` is `null`. In `tooling/bind/bind-outputs.mjs`, a deployment with no entry in
`custody_vault_urls` / `custody_broker_client_ids` is now skipped for that row (omitted loudly) instead of refused, so a root
with no custody (e.g. example-shared) binds; a non-map, a sensitive output or a malformed entry is still refused.

## v0.14.2 — BIND binds per-deployment credential custody

No consumer change is required. `tooling/bind/bind-outputs.mjs` classifies `custody_vault_urls` and
`custody_broker_client_ids` (maps keyed by deployment name: the custody vault endpoint URL and the workload-identity
client id the credential broker runs as) into secret-inputs `credentialCustody.vaultUrl` / `credentialCustody.brokerClientId`,
selecting the entry by `--deployment <name>` (default: the root's `deployment_name` output). Absent or null maps are omitted
loudly. `deployment_name` is classified `ignore`: it is a key, not a binding.

## v0.14.1 — `vm_id` output on the management runner (Azure)

No consumer change is required. `providers/azure/management-runner` gains the `vm_id` output (resource id of the
runner VM), and `stacks/azure/xema-foundation` includes it as `vm_id` in its `management_runner` output object.

## v0.14.0 — management runner denies VNet-wide inbound (Azure)

Behaviour change. `providers/azure/management-runner` now always adds an inbound DenyAll NSG rule (priority 4096)
above Azure's default `AllowVnetInBound`, and keeps only `AzureLoadBalancer` (110) and the `allowed_ssh_cidrs` SSH
rule (100) as allows. Inbound from the VNet and any routed customer network is denied by default, so add
`allowed_ssh_cidrs` for any SSH you need (including from inside the network). There is no input to disable it. The
module gains outputs `network_security_group_id` and `network_security_group_name` for attaching further rules
(use priorities 120-4095). Applying updates the NSG in place.

## v0.13.1 — `key_vault_id` output (Azure substrate)

No consumer change is required. `stacks/azure/xema-substrate` gains the `key_vault_id` output (`null` when
`enable_secrets_backend = false`). Reference the vault by it instead of constructing the id from `key_vault_name`:
the output carries a real dependency on vault creation, which a name-built id lacked and raced on a fresh apply.

## v0.13.0 — optional node pool OS disk (Azure)

No consumer change is required: the new inputs are optional and unset (`null`) keeps today's behaviour.

- `providers/azure/cluster`: optional `os_disk_size_gb` and `os_disk_type` ("Managed" or "Ephemeral") on every
  node pool, system and user. `Ephemeral` requires `os_disk_size_gb` (the disk must fit the VM cache); other
  values fail validation. Changing either on an existing pool replaces it.
- `stacks/azure/xema-substrate` (`node_pools[*].os_disk_size_gb`, `os_disk_type`) passes them through. Module
  README refs read `?ref=v0.13.0`.

## v0.12.1 — optional `postgres_zone` (Azure substrate)

No consumer change is required: the new input is optional and unset (`null`) keeps today's regional placement.

- `stacks/azure/xema-substrate`: optional `postgres_zone` ("1", "2" or "3"; `null` by default), passed to
  `providers/azure/managed-postgres` as `zone`. Set it before the first apply: changing it later replaces
  the server. Other values fail validation. Module README refs read `?ref=v0.12.1`.

## v0.12.0 — zone pinning (Azure) and the last `_v1` kubernetes moves

No consumer change is required: every new input is optional and unset keeps Azure's own zone choice,
so configuration only tightens. Pin a zone when the subscription marks one `NotAvailableForSubscription`
for a VM family (the resource SKUs API shows it).

- `providers/azure/management-runner`: optional `zone` ("1", "2" or "3"; empty by default).
- `providers/azure/cluster`: optional `zones` on every node pool, system and user (each "1", "2" or "3";
  unset by default). Changing `zones` on an existing pool replaces it.
- `stacks/azure/xema-foundation` (`management_runner.zone`) and `stacks/azure/xema-substrate`
  (`node_pools[*].zones`) pass them through. Values outside 1|2|3 fail validation.
- `cluster-addons/rwx-storage`, `secrets`, `workload-namespaces` and `shared-templates-volume` move to
  `kubernetes_storage_class_v1`, `_secret_v1`, `_namespace_v1`, `_persistent_volume_v1` and
  `_persistent_volume_claim_v1`. `moved {}` blocks migrate state with no destroy and no state surgery;
  `tofu validate` is free of deprecation warnings. Imports (module READMEs, `docs/import-runbook.md`) now
  name the `_v1` addresses, and module README refs read `?ref=v0.12.0`.

## Unreleased — `assigned_role_names`: the stack publishes the roles it assigns

A bootstrap no longer hand-copies the role list into its RBAC-Administrator ABAC condition (v0.10.0's
registry module assigned `AcrPull` and no copy had it). New `modules/assigned-roles` (no providers, no
resources) returns a static, sorted, de-duplicated `assigned_role_names` from `enable_cluster`,
`enable_container_registry`, `enable_dns`, `enable_secrets_backend`; the azure substrate stack outputs the
same list. The cluster, container-registry, dns and secrets-backend modules each output
`assigned_role_names`. CI (`tooling/check-assigned-roles.mjs`, `tofu test`) fails when any
`role_definition_name` is missing from the list. A bootstrap should derive its ABAC condition from
the module (modules/assigned-roles/README.md) and drop its copy.

## Unreleased — deployer-identity on the `_v1` kubernetes resources

No consumer change: `moved {}` blocks migrate existing state (`kubernetes_namespace`,
`_service_account`, `_secret`, `_role`, `_role_binding`, `_cluster_role`, `_cluster_role_binding` to
their `_v1` forms, and the `kube-system` data source) with no destroy, and `tofu validate` is free
of deprecation warnings. Imports now name the `_v1` addresses.

## Unreleased — optional container registry and the kubelet identity (Azure)

Adopting it needs nothing of a consumer root except one thing: the foundation's
`private_link_services` default now includes `acr`, so a re-plan of the foundation adds the
`privatelink.azurecr.io` zone and its VNet link (a root that sets the list itself must add `acr`
before enabling the registry). Everything else defaults to the previous behaviour.

- `stacks/azure/xema-substrate`: `enable_container_registry` (default `false`) and
  `container_registry_name` create a Premium, admin-off, public-endpoint-off registry
  (`modules/providers/azure/container-registry`) behind a private endpoint, with `AcrPull` for the
  kubelet identity. New outputs `container_registry_login_server`, `container_registry_id`,
  `kubelet_identity_object_id`, and the same three keys in `substrate`. The CI identity that pushes
  images is not created: grant `AcrPush` to your own CI principal.
- `providers/azure/network` and `providers/azure/private-endpoint`: `acr` joins the closed service set.

## Unreleased — settable PostgreSQL extensions (Azure)

No consumer change: the new input defaults to the previous behaviour. `managed-postgres`
gains `extensions` (`list(string)`, default `[]`, entries `^[a-z][a-z0-9_]*$`); non-empty
writes the `azure.extensions` server parameter as the sorted, distinct, comma-joined list,
empty creates no parameter. `stacks/azure/xema-substrate` threads it as `postgres_extensions`.

## Unreleased — Gateway API replaces ingress-nginx (BREAKING)

**Breaking, no compatibility alias.** `cluster-addons/ingress-tls` is deleted; its
replacement is `cluster-addons/gateway-tls`. A consumer root on the previous tag must:

- Swap the module source `.../cluster-addons/ingress-tls` for `.../cluster-addons/gateway-tls`.
  Gone: `ingress_nginx_*`, `ingress_class_name`, `ingress_default_class`, `ingress_replica_count`,
  `ingress_service_annotations`, `ingress_load_balancer_ip`, and the outputs
  `ingress_service_name`, `ingress_namespace`, `ingress_class_name`. New: `gateway_implementation`
  (`nginx-gateway-fabric` | `customer-managed`), `customer_gateway`, `gateway_hostname`,
  `route_namespaces`, `gateway_infrastructure_annotations`, `data_plane_*`, `ngf_*`, and
  `max_request_body_mib` (default 256, the `ClientSettingsPolicy` body ceiling); output
  `gateway_parent_ref` (`{ name, namespace, section_name }`). Pinned: Gateway API CRDs v1.6.1
  (standard channel, vendored), NGINX Gateway Fabric chart 2.7.2, cert-manager v1.21.2 with
  `enableGatewayAPI`. The HTTP-01 solver is now a Gateway `HTTPRoute`; `dns01-azure` is unchanged.
- In `stacks/azure/xema-substrate` and `examples/azure`: `enable_ingress_tls` is `enable_gateway_tls`,
  `ingress_service_annotations` is `gateway_infrastructure_annotations`, `ingress_load_balancer_ip`
  is `gateway_load_balancer_ip`; `gateway_hostname` is required with `nginx-gateway-fabric` and
  `workload_namespaces` become the namespaces whose `HTTPRoute`s may attach. New output
  `gateway_parent_ref`. The `substrate.ingress` key is `substrate.gateway`
  (`{ parent_ref, cluster_issuer_name }`); the DigitalOcean stack's is `null`.
- `tooling/bind/bind-outputs.mjs` reports `substrate.gateway` as an operator step (the
  `gateway.parentRef` block for `deployments/<d>/values.yaml`); it is never written to
  `secret-inputs.yaml`.

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
- **`cluster-addons/external-secrets` (new), split out of `cluster-addons/ingress-tls`.**
  The External Secrets Operator and its `ClusterSecretStore` are their own add-on:
  workloads need their secrets whatever serves inbound traffic — an ingress
  controller from this module set, a cloud provider's managed one, or none yet.
  `ingress-tls` keeps ingress-nginx, cert-manager and the `ClusterIssuer`, and loses
  `external_secrets_*`, `secret_store_backend`, `azure_key_vault_store`,
  `cluster_secret_store_name` and that output. The Azure stack installs the new
  add-on whenever `enable_secrets_backend` is set — **behaviour change:** no longer
  only together with `enable_ingress_tls`. Its outputs are unchanged.
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
kubeconfig ALIAS — the same cluster is `cluster-a` in one operator's file and
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
