# `cluster-addons/external-secrets`

The [External Secrets Operator](https://external-secrets.io) and the one `ClusterSecretStore`
(default name `platform`) every `ExternalSecret` references. Today's backend: Azure Key Vault
through workload identity (`providers/azure/secrets-backend` supplies the reader identity).

Separate from `cluster-addons/ingress-tls` because secrets are needed from the first workload
on, whatever serves inbound traffic — an ingress controller from this module set, a cloud
provider's managed one, or none yet.
