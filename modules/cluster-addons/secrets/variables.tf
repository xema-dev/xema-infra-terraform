variable "secrets" {
  description = <<-EOT
    Operator-provided credentials to materialize as Kubernetes Secrets, keyed by a
    stable id. Each entry:
      - name      : the Secret's metadata.name (defaults to the map key)
      - namespace : the namespace to create it in (must already exist)
      - type      : Kubernetes Secret type (default "Opaque"; e.g.
                    "kubernetes.io/dockerconfigjson" for a registry pull secret)
      - data      : string key/value pairs stored as the Secret data (sensitive;
                    stored base64 by the provider)
      - labels    : optional metadata labels

    This is the management-plane "secret backend": the source the Helm values
    reference via `secretKeyRef`. v1 materializes values supplied to Terraform; it
    can later be swapped for an external-secrets/Vault backed flow without changing
    consumers (the Secret names stay the contract).
  EOT
  type = map(object({
    name      = optional(string)
    namespace = string
    type      = optional(string, "Opaque")
    data      = map(string)
    labels    = optional(map(string), {})
  }))
  default = {}
  # NOTE: not marked `sensitive` at the variable level — Terraform forbids
  # for_each over a sensitive value (keys would leak into resource addresses).
  # The credential payload is protected where it matters: `data` is wrapped in
  # `sensitive()` in main.tf and the kubernetes_secret `data` attribute is
  # sensitive in the provider schema, so values are redacted in plan output.
  # Supply real values via TF_VAR_* / a sops-decrypted tfvars, never committed.
}
