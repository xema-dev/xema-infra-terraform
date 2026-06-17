# Extension / biome substrate

A way to provision **dedicated cloud substrate for a biome (or any extension)**
that isn't otherwise modelled in Terraform — without hand-writing a new module per
biome.

## When you need this (and when you don't)

Most biomes need **no** Terraform at all. A biome runs *in* the cluster and, when
it needs storage, gets a **schema on the shared platform database**, provisioned at
runtime by the platform's biome installer. That path is owned by the platform, not
Terraform. **Do not** model every biome here.

You need an extension claim **only** when a biome requires a **dedicated
out-of-cluster cloud resource** the runtime installer cannot create:

- its **own** managed database (hard isolation, not a shared schema),
- a dedicated **object-storage bucket**,
- a public **DNS hostname** of its own.

If a biome needs none of those, it needs no entry here. This keeps the mechanism an
**escape hatch**, not a parallel provisioning system — which is what makes it
robust instead of confusing.

## The contract: a closed set of claim kinds

An extension declares a **claim** — a typed request for substrate. Claims are a
**closed, enumerated set**. v1 ships three kinds:

| Kind | Provisions | Backed by primitive |
| --- | --- | --- |
| `object_buckets` | a dedicated object-storage bucket | `providers/<cloud>/object-bucket` |
| `managed_databases` | a dedicated logical database (+ optional owner role) on the **resolved** managed Postgres cluster | `digitalocean_database_db` / `_user` |
| `dns_records` | a DNS record pointing at the ingress/LB (requires `enable_dns`) | `providers/<cloud>/dns` |

### `managed_databases` — the resolved cluster

A `managed_databases` claim becomes a `digitalocean_database_db` (and, when it
declares an `owner`, a `digitalocean_database_user`) on the **resolved**
managed-Postgres cluster:

- in **greenfield** mode (`enable_managed_postgres = true`) that is the created
  `module.postgres`;
- in **consume** mode (`enable_managed_postgres = false`) that is the existing
  shared cluster named by `var.existing_database_cluster_id`.

These are **additive** — they create only the claimed databases/roles and never
touch the other databases on a shared cluster (so a subset can be managed safely).
If **neither** path resolves a cluster (managed Postgres disabled AND no
`existing_database_cluster_id`), the claim **fails fast** with a precondition
error rather than silently dropping the database.

`dns_records` claims likewise require `enable_dns = true`; if DNS is disabled for
the deployment, a declared `dns_records` claim **fails fast** (DNS is managed
elsewhere — remove the claim or enable the dns module).

Adding a kind later (e.g. `managed_redis`, `tls_certificate`) is a bounded change —
see [CONVENTIONS.md](CONVENTIONS.md). The set stays closed so the blast radius and
the mental model stay small.

## Shape

The stack accepts one `extensions` input — a map **keyed by extension id** (the
biome id), each value carrying any subset of the claim kinds:

```hcl
extensions = {
  # biome id => its substrate claims
  "acme/legal-review" = {
    object_buckets = {
      evidence = { name = "acme-legal-evidence", versioning = true }
    }
    dns_records = {
      portal = { name = "legal.acme", type = "CNAME", value = "ingress.xema.dev." }
    }
  }

  "acme/data-warehouse" = {
    managed_databases = {
      main = { database = "ext_data_warehouse", owner = "data_warehouse" }
    }
  }
}
```

Keys are stable ids, so adding/removing a biome adds/removes only its own resources
(`for_each` keyed by `"<biome>/<claim>"`) — never a destroy-and-recreate of
unrelated resources.

## How it is wired (no magic)

There is deliberately **no** clever cloud-agnostic "extensions" resource module —
Terraform can't pass a module as a value, and hiding the dispatch would make it
confusing. Instead the **cloud stack** wires claims to that cloud's primitives with
plain `for_each`:

```hcl
# stacks/<cloud>/xema-substrate/extensions.tf  (illustrative)
locals {
  ext_buckets = merge([for bid, e in var.extensions :
    { for k, v in lookup(e, "object_buckets", {}) : "${bid}/${k}" => v }]...)
  ext_dbs = merge([for bid, e in var.extensions :
    { for k, v in lookup(e, "managed_databases", {}) : "${bid}/${k}" => v }]...)
  ext_dns = merge([for bid, e in var.extensions :
    { for k, v in lookup(e, "dns_records", {}) : "${bid}/${k}" => v }]...)
}

module "extension_bucket" {
  source   = "../../../modules/providers/digitalocean/object-bucket"
  for_each = local.ext_buckets
  name     = each.value.name
  region   = var.region
  # ...
}

# managed_databases → digitalocean_database_db/_user on the RESOLVED cluster
# (created module.postgres, or var.existing_database_cluster_id when consuming):
resource "digitalocean_database_db" "extension" {
  for_each   = local.ext_databases
  cluster_id = local.ext_db_cluster_id # module.postgres id, else existing id
  name       = each.value.database
}
# dns feeds module.dns.records (requires enable_dns)
```

The claim **shape** is identical across clouds (it's the contract); only the
`module` sources differ per cloud. That is the whole mechanism.

## Where the values come from

- **By hand:** an operator writes the `extensions` map in their private `*.tfvars`.
  Fine for a handful of biomes.
- **Generated:** the operator's private config ships a small generator that reads
  installed biome manifests for an optional substrate block and emits the
  `extensions` tfvars. The generator is **Xema-specific** (it understands the biome
  manifest format) so it lives in the operator's **private** repo, not here — this
  public module stays a generic, manifest-agnostic, claim-driven primitive. Anyone
  can drive it from any source.

## Boundary recap

- Terraform extension claims = **dedicated, out-of-cluster** substrate only.
- Shared-database schemas, in-cluster resources, and biome installation itself
  stay owned by the **platform runtime**. Terraform never reaches into them.
- A claim is **additive and isolated**: present only for biomes that genuinely need
  dedicated substrate.
