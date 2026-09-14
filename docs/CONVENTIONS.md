# Module authoring conventions

Follow these so every module looks the same and the repo stays adoptable.

## File layout (per module)

Every module directory contains exactly these files (omit a file only if it would
be empty):

| File | Holds |
| --- | --- |
| `versions.tf` | `terraform { required_version }` + `required_providers` block. |
| `variables.tf` | every input, each with a `description` and explicit `type`. |
| `main.tf` | resources/data sources only. |
| `outputs.tf` | every output, each with a `description`. |
| `README.md` | purpose, the contract it implements, inputs/outputs table, example. |

## Style

- Terraform `>= 1.6` (the `optional()` object attributes and `import {}` blocks are
  used throughout).
- `snake_case` for variables, outputs, locals, and resource local names.
- The primary resource in a single-resource module is named `this`.
- Every `variable` has a `description` and an explicit `type`. Every `output` has a
  `description`. Outputs carrying credentials set `sensitive = true`.
- Closed sets are validated with a `validation` block listing the allowed values —
  never accept a free-form string for a closed domain.
- No provider `provider {}` blocks inside reusable modules — only
  `required_providers` in `versions.tf`. The **root/stack** configures providers
  and passes them down. This keeps modules composable.
- No hardcoded account ids, regions, hostnames, project names, or any
  deployment-specific value. Everything deployment-specific is a variable with a
  generic default (or no default).

## State & secrets (critical — this is a PUBLIC repo)

- **Never** commit `*.tfstate`, real `*.tfvars`/`*.auto.tfvars`, or a real
  `backend.hcl`. The `.gitignore` enforces this and CI fails the build if any slip
  through. Only `*.example` variants are tracked.
- Reusable modules contain **no** `backend {}` block. Backends are a root concern;
  the stack/example ships a `backend.hcl.example` showing the shape.
- State lives in **remote object storage with locking** (DigitalOcean Spaces / AWS
  S3 / GCS / Azure Blob), in a **private** bucket, encrypted at rest. The
  `state-bucket` module bootstraps it; the backend then points at it.
- Operators keep their real values in a **private** configuration root that
  consumes these modules by a pinned `?ref=` source. Nothing private ever lands
  here.

## Adding a new cloud

1. Add `modules/providers/<cloud>/{cluster,managed-postgres,dns,object-bucket,state-bucket}`,
   each satisfying [CONTRACTS.md](CONTRACTS.md) — plus `secrets-backend` and
   `cache` when the cloud offers a managed equivalent (both optional primitives).
2. Copy a `stacks/<cloud>/xema-substrate` (DigitalOcean is the minimal shape,
   Azure the one with every optional primitive and the `ingress-tls` addon) and
   point each `module` block at the new `providers/<cloud>/*` sources. The
   cloud-agnostic modules and the extension wiring are copied verbatim.
3. Add an `examples/<cloud>/` with placeholder `terraform.tfvars.example` +
   `backend.hcl.example`.
4. CI auto-discovers and validates every directory containing `*.tf` — no workflow
   edit required.

## Adding a new extension claim kind

See [extensions.md](extensions.md). Adding a kind is a bounded change: one new
optional field on the `extensions` object variable + one `for_each` block per cloud
stack. Keep the kind set closed and documented.
