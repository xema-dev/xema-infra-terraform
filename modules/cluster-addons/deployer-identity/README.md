# `cluster-addons/deployer-identity`

Cloud-agnostic [`cluster-addons/deployer-identity`](../../../docs/CONTRACTS.md#cloud-agnostic-modules-no-per-cloud-implementation-needed)
module. The namespaces a deployment owns, the least-privileged ServiceAccount
its pipeline deploys as, that account's token, and the three facts that
identify the cluster it reaches — as infrastructure, in the same apply that
creates the cluster.

## Why it exists

A pipeline's kubeconfig is a **credential**, and only an identity that already
holds cluster-admin can mint one. That is the same identity the cluster's own
`apply` runs under. So the deployer belongs in the apply, and its kubeconfig
becomes an OUTPUT the deployment tooling consumes — exactly like a database
endpoint or a realm's client secret.

The alternative is a manifest somebody applies by hand with cluster-admin on
their laptop, once per deployment, re-applied from a runbook whenever a grant
changes. That is the step this module removes.

## What it creates

| | |
| --- | --- |
| `kubernetes_namespace` × N | the deployment's namespace + `additional_namespaces` (skippable: `manage_namespaces = false`) |
| `kubernetes_service_account` | one, in the deployment's namespace |
| `kubernetes_secret` | its `kubernetes.io/service-account-token`, waited for so the token is available in the same run |
| `kubernetes_role` + `kubernetes_role_binding` × N | the same least-privileged rule set in every namespace, all bound to the one account |
| `kubernetes_cluster_role` + binding | read-only `get` on exactly `kube-system` and the deployment's namespace (`manage_cluster_identity_reader`) |

**The authority is namespaced.** No ClusterRoleBinding for workloads, no
cluster-scoped write. A chart rendering a cluster-scoped resource fails
explicitly — that is an administrator's decision, never a permission to
pre-grant. The one cluster-scoped grant is read-only and limited by
`resourceNames`, and it exists so a deploy can PROVE which cluster it is
pointed at before it writes.

## Usage

```hcl
module "deployer_identity" {
  source = "github.com/xema-dev/xema-infra-terraform//modules/cluster-addons/deployer-identity?ref=v1.0.0"

  # EXAMPLE names — yours are what YOUR deployment declares.
  deployment_name       = "acme-prod"
  namespace             = "acme-prod"        # deployment.yaml#namespace, never a directory name
  additional_namespaces = ["acme-prod-infra"]

  # Cluster facts, from whatever owns the cluster — created here or consumed.
  cluster_endpoint           = module.cluster.endpoint
  cluster_ca_certificate_b64 = module.cluster.cluster_ca_certificate
}
```

Then, once:

```sh
tofu output -raw deployer_kubeconfig > /tmp/kubeconfig   # or: terraform output -raw
# hand it to whatever runs helm — a CI secret store, a vault, or the file itself
```

## The namespace is DECLARED, never derived

`namespace` is required with no default, and `additional_namespaces` has no
implicit `-infra` suffix. A namespace inferred from the directory that happens
to hold a deployment's files is the defect this shape refuses: it produced a
deployment declaring `xema-prod` whose tooling demanded a namespace named after
its folder. The cluster knows nothing about anybody's directory layout.

`deployment_name` is likewise not the namespace. It names the cluster-scoped
objects (which must be unique per deployment on a shared cluster) and labels the
namespaces, and the two are routinely different on a cluster that hosts more
than one environment.

## Cluster identity is three facts, and a context name is not one of them

`cluster_identity` emits the API server endpoint, the **sha256 of the decoded
cluster CA**, and the **UID of `kube-system`**. A consumer recomputes all three
— the digest from a flattened kubeconfig's `certificate-authority-data`, the
UID from one `get namespace` — and refuses to write when any differs.

A context name is deliberately absent. It is an alias chosen by whoever wrote
the kubeconfig, so the same cluster under a different alias is the same cluster:
a check that compares aliases refuses a correct target and admits a wrong one
that happens to share a name. `context_name` exists only so the emitted file
carries the alias a consumer still expects; nothing derives authority from it.

## Importing (adopting an existing bootstrap)

Every object is adoptable, which is how a cluster that was bootstrapped by hand
moves under Terraform without a re-apply. Namespaced ids are `<namespace>/<name>`:

```
tofu import 'module.deployer_identity.kubernetes_namespace.this["acme-prod"]'        acme-prod
tofu import  module.deployer_identity.kubernetes_service_account.deployer            acme-prod/github-deployer
tofu import  module.deployer_identity.kubernetes_secret.deployer_token               acme-prod/github-deployer-token
tofu import 'module.deployer_identity.kubernetes_role.deployer["acme-prod"]'         acme-prod/github-deployer
tofu import 'module.deployer_identity.kubernetes_role_binding.deployer["acme-prod"]' acme-prod/github-deployer
tofu import 'module.deployer_identity.kubernetes_cluster_role.cluster_identity[0]'         acme-prod-github-deployer-cluster-identity
tofu import 'module.deployer_identity.kubernetes_cluster_role_binding.cluster_identity[0]' acme-prod-github-deployer-cluster-identity
```

`manage_namespaces = false` is the other half: it leaves namespaces to whoever
owns them (the customer's platform team, or this repo's
[`workload-namespaces`](../workload-namespaces/README.md)) and still creates the
grants inside them.

## Rotating the token

`tofu taint` the token Secret and apply: a new token is minted, the kubeconfig
output changes, and the consumer re-binds it. No long-lived cluster-admin
credential exists anywhere in that chain.

| Input | Required | Description |
| --- | --- | --- |
| `deployment_name` | **yes** | names the cluster-scoped objects and labels the namespaces |
| `namespace` | **yes** | the namespace the deployment declares; holds the account and its token |
| `additional_namespaces` | no | every other namespace the same identity deploys into (default `[]`) |
| `service_account_name` | no | default `github-deployer`; the token Secret is `<name>-token` |
| `manage_namespaces` | no | default `true`; false leaves namespace ownership elsewhere |
| `namespace_labels` | no | extra labels merged over the two always set |
| `cluster_endpoint`, `cluster_ca_certificate_b64` | no (together) | supply both to emit a kubeconfig and the server/CA identity |
| `context_name` | no | alias written into the emitted kubeconfig (default `default`) |
| `manage_cluster_identity_reader` | no | default `true`; the read-only, `resourceNames`-limited cluster grant |
| `extra_rules` | no | extra NAMESPACED policy rules for every namespace |

Outputs: `namespaces`, `service_account_name`, `token_secret_name`,
`deployer_token` (sensitive), `deployer_kubeconfig` (sensitive, null without
cluster facts), `cluster_identity`.

## Notes

- The `kubernetes` provider is configured by the **root/stack**, not here (see
  [CONVENTIONS.md](../../../docs/CONVENTIONS.md)).
- This module does not grant the PLATFORM's own runtime identities (the
  workload-manager ClusterRole a runtime service holds, or a storage pool's PVC
  Role in a workers namespace). Those are different subjects with different
  authority and belong in their own module; this one is the pipeline's identity
  only.
