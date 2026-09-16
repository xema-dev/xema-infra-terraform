# Example — the customer-owned consumer root

What a customer's **private** repository carries for the substrate, and all of
it:

| file | what |
| --- | --- |
| `main.tf` | `module "substrate"` pinned to a RELEASED version (`?ref=v0.6.0`) + the outputs BIND reads |
| `variables.tf` | the inputs this deployment sets; everything else keeps the stack's default |
| `terraform.tfvars` (from `.example`) | the values — neutral placeholders here, yours there |
| `backend.hcl` (from `.example`) | where the state lives — the first binding a handoff moves |

**Two onboarding questions decide the engine, and nothing else does:**

1. *Does the customer mandate Terraform / HCP?* — yes → run `terraform`;
   no → run `tofu` (OpenTofu, the default engine).
2. *Is future Terraform portability required?* — default **yes** for
   customer-owned infrastructure. Every module here is `terraform-portable`
   (standard HCL, no OpenTofu-only construct, a backend both engines read), so
   the answer costs nothing today; it is recorded so a later `opentofu-native`
   module is never adopted into this root by accident.

The commands below say `tofu`; every one of them is the same with
`terraform` in its place. Same files, same state, no wrapper — see
`docs/CONTRACTS.md § Engine and authoring profile`.

**The required inputs are declared HERE and passed through.** A
`terraform.tfvars` (or `*.auto.tfvars.json`) sets variables of this ROOT, not
of the stack: `platform_databases`, `workload_namespaces` and the other
required inputs are each a `variable` in `variables.tf` and a
`<name> = var.<name>` line in `main.tf`'s module block. A root that declares
one without passing it — or passes one it never declared — fails with `The
argument "platform_databases" is required` no matter what the tfvars says.

**Module version + tfvars. Never a forked stack.** Adopting a release is a
one-line `?ref=` change, `terraform init -upgrade`, and a plan that is
reviewed — the [CHANGELOG](../../CHANGELOG.md) names every input a release
adds or requires. A fork is a stack nobody upgrades; a pin is one everybody can.

## Run

```sh
cp terraform.tfvars.example terraform.tfvars   # edit: every value is yours
cp backend.hcl.example      backend.hcl        # edit: your state bucket
export AWS_ACCESS_KEY_ID=… AWS_SECRET_ACCESS_KEY=…          # state backend
export TF_VAR_do_token=… TF_VAR_keycloak_client_secret=…    # providers
tofu init -backend-config=backend.hcl
tofu apply -target=module.substrate.module.cluster          # greenfield only: phase 1
tofu apply                                                  # phase 2
```

Then BIND — the outputs into the deployment root's two input files, with no
credential typed by hand:

```sh
tofu output -json | node <xema-infra-terraform>/tooling/bind/bind-outputs.mjs \
  --secret-inputs ./secret-inputs.fragment.yaml --externals "$HOME/.config/acme/externals.json"
```

See [`tooling/bind/README.md`](../../tooling/bind/README.md) for the mapping,
and `docs/CONTRACTS.md § Three ownership modes` for who holds which of these
files in each mode.

## Validating this example offline

`main.tf`'s git source needs the network. This repository's CI validates every
root on BOTH engines with `-backend=false` and no network, so it first copies
`ci/source_override.tf.ci` to `source_override.tf` (git-ignored), which points
the module at the stack in the checkout under test. That override exists for
CI only; a customer root has no such file.
