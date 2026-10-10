# xema-infra-terraform

Reusable [Terraform](https://www.terraform.io) modules and stacks that provision the cloud substrate a [Xema](https://xema.dev) deployment runs on: a Kubernetes cluster, managed Postgres, DNS, object storage, a secrets backend, in-cluster prerequisites (namespaces, ReadWriteMany storage, Gateway and TLS) and the Keycloak identity realm.

The repo holds no deployment-specific values, secrets or state. You bring your own backend and variables.

## When to use it

- You need the cloud infrastructure underneath a Xema deployment, on Azure or DigitalOcean.
- You already have a cluster, database and DNS and only need the in-cluster and identity parts (consume mode).

Terraform stops at the substrate. It deploys no Xema application; those are deployed from `xema-deploy`.

## Usage

1. Copy [`examples/azure`](examples/azure) or [`examples/digitalocean`](examples/digitalocean) into your own private root.
2. Fill `terraform.tfvars` and `backend.hcl` from the `.example` files.
3. Run `terraform init -backend-config=backend.hcl`, `terraform plan`, then `terraform apply`.

Run Terraform locally as an operator. CI in this repo only lints.

To adopt infrastructure that already exists, follow [`docs/import-runbook.md`](docs/import-runbook.md) and apply only when the plan shows no changes.

## Modes

Each area has an `enable_*` input, default `true`.

| Mode | Settings | Result |
| --- | --- | --- |
| Greenfield | defaults | the stack creates cluster, Postgres, DNS, addons and realm |
| Consume | `enable_cluster`, `enable_managed_postgres`, `enable_dns` set to `false` | the stack manages only in-cluster and identity resources, reading the existing cluster by name |

## Required inputs

Both stacks require two rosters with no default, because the substrate does not know your applications:

| Input | Meaning |
| --- | --- |
| `platform_databases` | logical database names to create |
| `workload_namespaces` | full namespace names to create |

The Azure stack derives every other name from `deployment_name` (3-20 characters), and `environment` (`dev` or `prod`) sets the irreversible settings.

## Layout

| Path | Contents |
| --- | --- |
| [`modules/cluster-addons/`](modules/cluster-addons) | in-cluster addons for any cluster |
| [`modules/identity-realm/`](modules/identity-realm) | Keycloak realm, clients, roles, mappers |
| [`modules/postgres-tenancy/`](modules/postgres-tenancy), [`modules/assigned-roles/`](modules/assigned-roles) | database tenancy and role assignment |
| [`modules/providers/`](modules/providers) | Azure, DigitalOcean and Cloudflare implementations of the substrate contracts |
| [`stacks/azure/xema-substrate`](stacks/azure/xema-substrate) | the Azure substrate |
| [`stacks/digitalocean/xema-substrate`](stacks/digitalocean/xema-substrate) | the DigitalOcean substrate (being retired) |
| [`tooling/bind`](tooling/bind) | turns stack outputs into deploy bindings |
| [`examples/`](examples) | runnable examples with placeholder values |

Both stacks expose a `substrate` output with the same keys. Consumers bind to it as described in [`docs/CONTRACTS.md`](docs/CONTRACTS.md#binding-contract).

## Links

- [`docs/CONTRACTS.md`](docs/CONTRACTS.md): the interface every provider satisfies
- [`docs/CONVENTIONS.md`](docs/CONVENTIONS.md): module authoring and state handling
- [`docs/extensions.md`](docs/extensions.md): the extension substrate
- [`docs/import-runbook.md`](docs/import-runbook.md): adopting running infrastructure

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
