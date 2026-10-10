# Example: customer-owned consumer root

What a customer's private repository carries for the substrate.

| File | Purpose |
| --- | --- |
| `main.tf` | `module "substrate"` pinned to a released version, and the outputs `tooling/bind` reads |
| `variables.tf` | the inputs this deployment sets, including the `platform_databases` and `workload_namespaces` rosters |
| `terraform.tfvars.example` | placeholder values |
| `backend.hcl.example` | where the state lives |
| `ci/` | `source_override.tf.ci`, used by this repo's CI only |

A consumer root must declare `platform_databases` and `workload_namespaces` as its own variables and pass them into the module call.

## Usage

```sh
cp terraform.tfvars.example terraform.tfvars
cp backend.hcl.example      backend.hcl
export AWS_ACCESS_KEY_ID=...  AWS_SECRET_ACCESS_KEY=...
export TF_VAR_do_token=...    TF_VAR_keycloak_client_secret=...
tofu init -backend-config=backend.hcl
tofu apply -target=module.substrate.module.cluster   # greenfield only
tofu apply
```

`terraform` works the same in place of `tofu`. Then bind the outputs into the deployment root with [`tooling/bind`](../../tooling/bind).

Pin a released version and upgrade by changing the `?ref=`; the [CHANGELOG](../../CHANGELOG.md) lists the inputs each release adds. To avoid a runtime dependency on this repository, vendor the release tarball and use a relative `source` into it; the stacks reference their modules by relative path.
