# xema-infra-terraform

Reusable, cloud-agnostic [Terraform](https://www.terraform.io) modules that
provision the **cloud substrate** a [Xema](https://xema.dev) deployment runs on —
**everything that must exist before `kubectl`/`helm` can apply**:

- a Kubernetes cluster + node pools,
- a managed Postgres database,
- DNS,
- the ReadWriteMany **StorageClass + NFS provisioner**,
- the cluster-prerequisite **namespaces**,
- the **Keycloak identity realm** (realm + clients + roles + mappers),
- and a generic **extension substrate** mechanism for consumers that need
  their own dedicated cloud resources.

It is **Apache-2.0** and carries **no deployment-specific values, secrets, or
state** — adopt it for your own cloud, wire it to your own backend, and pass your
own values. Xema operators consume it from a private configuration root (see
[Private vs public](#private-vs-public)).

## Two modes — create or consume

Each substrate area is independently toggleable via an `enable_*` input (all
default to `true`), so the stack runs in either of two modes:

- **Greenfield (default):** enable everything → the stack CREATES the cluster,
  managed Postgres, DNS, in-cluster addons, and realm from nothing.
- **Consume:** set `enable_cluster = false`, `enable_managed_postgres = false`,
  `enable_dns = false` when a SEPARATE "cloud substrate" Terraform (owned by
  another team) already provides the cluster / DB / DNS. The stack then manages
  ONLY the in-cluster and identity resources (namespaces, RWX storage, realm,
  extension claims) and **consumes** the existing cluster by name — no two-phase
  apply needed, because the cluster is read via a data source rather than
  created in the same pass. Extension databases land on
  `existing_database_cluster_id`.

This is the **in-cluster vs cloud-infra split**: the same modules either own
the whole substrate or just the parts a deployment adds on top of someone
else's cloud. See the
[stack README](stacks/digitalocean/xema-substrate/README.md#two-modes--greenfield-vs-consume).

## How it runs — locally, by an operator

This Terraform is **run locally by an operator** (`terraform plan` / `apply` /
`import` from a workstation), **not** from a CI/CD pipeline. The repo's CI only
**lints** (`fmt` / `validate` / `tflint` / a secret-leak scan) — it never plans or
applies against real infrastructure. Apply/import deliberately stay a manual,
reviewed, local action. (App deploys remain owned by the separate Helm GitOps
pipeline — see the table below.)

## Who consumes these modules

These are **library modules** consumed by per-deployment roots that live
elsewhere. Every consumer is a **private root** (its own backend, tfvars and
state) that references these modules by a pinned `?ref=`; the shape of such a
root is what `examples/<cloud>/` shows. Consumers today, all **cloud**
Kubernetes:

| Consumer | Mode | Uses |
| --- | --- | --- |
| `xema-deploy` → `terraform/live/xema-prod` | **consume** (cluster/DB/DNS already exist) | reads the cluster by name; manages the in-cluster and identity resources (namespaces, RWX storage, realm, extension claims) |
| `xema-control-plane` → `terraform/management-plane` | **greenfield** (creates the management cluster) | `cluster` + `dns` + object storage + `identity-realm` + `cluster-addons/secrets` for the fleet management plane (Rancher Fleet / Headscale / Teleport host) |
| a per-deployment private root on **Azure** (one per customer deployment, kept in that deployment's own private repository) | **greenfield** or **consume** | `stacks/azure/xema-substrate` — everything derived from one `deployment_name` (see [The Azure stack](#the-azure-stack)) |

**On-prem appliances are NOT a consumer.** The `xema-appliance` fleet edge is a
single-node **k3s** box brought up by **ansible** + bootstrap scripts and
reconciled by Rancher Fleet — it does not use this Terraform. In particular the
`cluster` module is a managed-cloud cluster (not k3s) and `cluster-addons/rwx-storage`
is a **multi-node** ReadWriteMany NFS class that does not apply to a single-node
appliance (which uses k3s local-path). This repo is the **cloud** plane only.

## The stacks — capabilities, not applications

**The infrastructure layer must be usable without the platform running at
all.** It deals in capabilities — Kubernetes, PostgreSQL, Redis, object
storage, DNS/ingress, secret authority — and must not know application
concepts: no service, no biome, no roster of who runs where. The consumer
binds to a substrate through the stable
[binding contract](docs/CONTRACTS.md#binding-contract) (the `substrate`
output, same key shape on every cloud); it does not own the infrastructure's
architecture. That is why the two rosters the substrate cannot know — which
databases exist (`platform_databases`) and which namespaces exist
(`workload_namespaces`) — are **required inputs with no default** on every
stack: the consumer derives them from its own distribution, and a stack
invoked without them refuses to plan. The `examples/` pass explicit rosters,
labelled as one deployment's example and never a default.

**DigitalOcean is being retired (everything moves to owl), so its stack is left untouched: it gets no consume-mode database/role path, and its `platform_databases` stay verbatim.**

### The Azure stack

[`stacks/azure/xema-substrate`](stacks/azure/xema-substrate/README.md) is the
second full implementation of the substrate, and it adds three optional
primitives the DigitalOcean stack does not have — a **secrets backend**
(Key Vault + External Secrets), an optional **managed cache**, and the
cloud-agnostic **`ingress-tls`** addon (ingress-nginx, cert-manager +
`ClusterIssuer`, External Secrets + `ClusterSecretStore`). Three properties
decide its shape:

- **One input names everything the substrate owns.** `deployment_name`
  (validated, 3-20 chars) derives the cluster, server, storage account, vault,
  the app and provisioner roles, the blob container prefix, the realm, and the
  prefix of every database (`<dep>_<name>` for each name in
  `platform_databases`). `environment` (`dev | prod`) decides the irreversible
  knobs. The only rewrite is hyphen → underscore for Postgres identifiers.
  Namespaces are NOT derived: `workload_namespaces` is passed by full name.
- **Workload identity, no stored cloud credentials.** AKS runs with the OIDC
  issuer on; cert-manager's DNS-01 solver and External Secrets each get a
  user-assigned identity federated to their service account, scoped to the one
  zone / vault they touch.
- **The `substrate` output map** carries the non-secret facts a consumer binds
  to (hosts, ports, names, endpoints, the ingress hint, the realm);
  credentials stay in separate sensitive outputs. The DigitalOcean stack
  exposes the same map with the same keys.

Read the stack README's
[apply-order section](stacks/azure/xema-substrate/README.md#apply-order-on-a-greenfield-cluster-read-this)
before a greenfield apply: three providers connect to things the stack
creates, and the Postgres roles need the operator to reach a private server.

## What this is NOT

This repo is the **substrate plane** only. Three planes, one owner each:

| Plane | Owner | Scope |
| --- | --- | --- |
| **A — Substrate** | **this repo (Terraform)** | cluster, managed DB, DNS, StorageClass, namespaces, realm |
| **B — Platform apps** | Helm GitOps (`xema-deploy`) | every Xema service that runs *in* the cluster |
| **C — Local dev** | docker-compose (`xema-monorepo/test-suite`) | local development |

**Terraform stops at the substrate.** It deploys **no** Xema application via
`helm_release` — app deploys stay owned by the Helm GitOps pipeline so deploy
ownership is never split across two systems. Self-hosted *in-cluster* backing
infra (etcd / valkey / minio / …) is **Helm**, not Terraform, because it runs in
the cluster.

This is also **not** [`xema-terraform-provider`](https://github.com/xema-dev/xema-terraform-provider).
That provider provisions **platform tenancy** (orgs, projects, models) against a
running Xema control-plane — a different axis. This repo provisions the **cloud
infrastructure** the platform itself runs on. They compose but never overlap.

## Layout

```
modules/
  cluster-addons/
    rwx-storage/          # ReadWriteMany StorageClass (+ optional NFS provisioner) (any cluster)
    workload-namespaces/  # a roster of prerequisite namespaces (any cluster)
    shared-templates-volume/ # one RWX NFS export shared across N namespaces (any cluster)
    secrets/              # operator-provided credentials as Kubernetes Secrets (any cluster)
    ingress-tls/          # ingress-nginx + cert-manager/ClusterIssuer + External Secrets/ClusterSecretStore (any cluster)
  identity-realm/         # full Keycloak realm config (any Keycloak)
  providers/
    digitalocean/         # DigitalOcean implementations of the substrate contracts
      cluster/            #   DOKS + node pools + VPC
      managed-postgres/   #   DO managed Postgres + logical DBs/roles
      dns/                #   DO DNS domain + records
      object-bucket/      #   DO Spaces bucket (application/extension use)
      state-bucket/       #   DO Spaces bucket for Terraform state (bootstrap)
    azure/                # Azure implementations of the substrate contracts
      cluster/            #   AKS + node pools + VNet (delegated Postgres subnet), workload identity
      managed-postgres/   #   PostgreSQL Flexible Server + logical DBs/roles + grants
      dns/                #   Azure DNS zone + records (+ DNS-01 workload identity)
      object-bucket/      #   storage account (+ containers) for application/extension blobs
      state-bucket/       #   storage account + container for Terraform state (bootstrap)
      secrets-backend/    #   RBAC Key Vault + External Secrets reader identity
      cache/              #   Azure Cache for Redis (optional)
    cloudflare/           # Cloudflare edge settings long-lived connections depend on
      edge/               #   WebSocket proxying held on for the consumer's declared paths; Argo pinned off
stacks/
  digitalocean/
    xema-substrate/       # composes the DO primitives into one deployable substrate
  azure/
    xema-substrate/       # composes the Azure primitives; every name derived from deployment_name
examples/
  digitalocean/           # runnable example with placeholder values
  azure/                  # runnable example with placeholder values
docs/
  CONTRACTS.md            # the cloud-agnostic interface every provider must satisfy
  CONVENTIONS.md          # module authoring conventions
  extensions.md           # the generic extension substrate mechanism
  import-runbook.md       # adopting already-running infra with zero-change plans
```

## Quick start (your own cloud)

1. Read [`docs/CONTRACTS.md`](docs/CONTRACTS.md) — the input/output interface each
   substrate primitive must satisfy.
2. To run on **DigitalOcean**, copy [`examples/digitalocean`](examples/digitalocean)
   and fill in `terraform.tfvars` + `backend.hcl` from the `.example` files.
3. To run on **Azure**, copy [`examples/azure`](examples/azure) — one
   `deployment_name` derives everything; see [The Azure stack](#the-azure-stack).
4. To run on **another cloud**, add `modules/providers/<cloud>/{cluster,managed-postgres,dns,object-bucket,state-bucket}`
   satisfying the contracts (plus `secrets-backend` / `cache` if that cloud offers
   them), then copy a `stacks/<cloud>/xema-substrate` and swap the module sources.
   Nothing else changes — the cloud-agnostic modules (`cluster-addons/*`,
   `identity-realm`) and the stack shape are reused as-is.

## Adopting already-running infrastructure

If your substrate already exists (the common case for an operating deployment),
**do not** let Terraform recreate it. Follow
[`docs/import-runbook.md`](docs/import-runbook.md): write `import {}` blocks,
reconcile HCL until `terraform plan` reports **0 to add, 0 to change, 0 to
destroy**, and only then apply. A plan that wants to replace or destroy a live
cluster or database is a bug in your HCL — fix it, never apply it.

## Private vs public

This public repo holds **only reusable modules + examples with placeholder
values**. An operator's real configuration — backend, `*.tfvars`, secrets, and
state — lives **outside** this repo, in a private root that references these
modules by a pinned version. State lives in remote object storage (e.g. a private
DigitalOcean Spaces / S3 / GCS / Azure Blob bucket) with locking, **never** in any
git repository. See [`docs/CONVENTIONS.md` § State & secrets](docs/CONVENTIONS.md).

## Version notes

### Unreleased — next MAJOR (breaking: the stacks' variable contract)

The boundary above became law in the code. Both stacks and three modules now
refuse to plan without inputs that used to be defaulted or derived to one
deployment's roster:

| Where | New REQUIRED input (no default) | Replaces |
| --- | --- | --- |
| `stacks/azure/xema-substrate` | `platform_databases` — `set(string)`, unprefixed logical names, each prefixed `<deployment_name as _>_` | the thirteen derived databases, `enable_billing_database` and `postgres_extra_databases` (all deleted) |
| `stacks/azure/xema-substrate` | `workload_namespaces` — `set(string)`, full names, DNS-1123 | the five derived namespaces and `extra_workload_namespaces` (deleted) |
| `stacks/digitalocean/xema-substrate` | `platform_databases` — `set(string)`, verbatim (`[]` when consuming) | `postgres_databases` (renamed; had a default) |
| `stacks/digitalocean/xema-substrate` | `workload_namespaces` — `set(string)`, full names, DNS-1123 | its seven-namespace default (deleted) |
| `modules/cluster-addons/workload-namespaces` | `namespaces` | its seven-namespace default (deleted) |
| `modules/cluster-addons/shared-templates-volume` | `owner_namespace`, `owner_pvc_name`, `consumer_mounts` (`map(namespace => claim)`), `name_prefix` | `orchestrator_namespace`, `workers_namespace`, `orchestrator_pvc_name`, `workers_pvc_name` and their defaults; resources are now `owner` + `consumer[<ns>]` (state addresses change); the `shared_templates_pool_slug` output is deleted |
| `modules/providers/cloudflare/edge` | `websocket_paths` — `set(string)`, each starting with `/` (`[]` declares none) | prose that named the paths; a plan turning `websockets_enabled` off while paths are declared is now REFUSED |

Also in this change: the DigitalOcean stack gains the `substrate` output with
the same key shape as Azure's (the [binding contract](docs/CONTRACTS.md#binding-contract)),
and a `postgres_databases` output; the Azure `substrate.namespaces` entry is
the ensured roster (`set(string)`) instead of a role-keyed map, and
`postgres_app_role` / `postgres_provisioner_role` / `postgres_databases` /
`blob_container_prefix` in that map — and the top-level `postgres_databases` /
`postgres_roles` outputs — are `null` when their area is disabled, as the map's
description always said; the Azure `realm_display_name` default is
`deployment_name` verbatim. `extensions` keeps its name — its docs now say
"extension id" rather than "biome id". To adopt: pass the rosters you already
deploy (the `examples/*.tfvars.example` files show one deployment's), and
`terraform plan` must report **0 to add, 0 to change, 0 to destroy** on an
existing deployment before you apply.

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
