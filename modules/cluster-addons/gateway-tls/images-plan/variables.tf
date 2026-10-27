variable "ngf_images" {
  description = <<-EOT
    Image overrides for NGINX Gateway Fabric (`controller` = the control plane, `nginx` = the data plane it launches), keyed by component (`controller`, `nginx`); empty (the default) keeps the chart's own images.
    Each entry sets the full image repository (registry host and path, no tag or digest), a tag, and a REQUIRED
    sha256 digest, so a registry override can never be tags-only. Rendered into nginxGateway.image.* and nginx.image.* with the tag value `<tag>@<digest>` (the chart has no digest key and renders repository:tag).
  EOT
  type = map(object({
    repository = string
    tag        = string
    digest     = string
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for k in keys(var.ngf_images) : contains(["controller", "nginx"], k)])
    error_message = "ngf_images keys must be among: controller, nginx."
  }

  validation {
    condition     = alltrue([for v in values(var.ngf_images) : can(regex("^sha256:[0-9a-f]{64}$", v.digest))])
    error_message = "ngf_images: every entry needs a digest of the form sha256:<64 lowercase hex characters>; tag-only image overrides are refused."
  }

  validation {
    condition     = alltrue([for v in values(var.ngf_images) : can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?(/[a-z0-9._-]+)+$", v.repository))])
    error_message = "ngf_images: repository must be a registry host (optional port) and path such as 10.0.0.1/proj/image, without a scheme, tag or digest."
  }

  validation {
    condition     = alltrue([for v in values(var.ngf_images) : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", v.tag))])
    error_message = "ngf_images: tag must be a valid image tag (it is rendered as <tag>@<digest>)."
  }
}

variable "cert_manager_images" {
  description = <<-EOT
    Image overrides for cert-manager, keyed by component (`controller`, `webhook`, `cainjector`, `acmesolver`, `startupapicheck`); empty (the default) keeps the chart's own images.
    Each entry sets the full image repository (registry host and path, no tag or digest), a tag, and a REQUIRED
    sha256 digest, so a registry override can never be tags-only. Rendered into image.*, webhook.image.*, cainjector.image.*, acmesolver.image.* and startupapicheck.image.* as repository + tag + digest (the chart has a digest key).
  EOT
  type = map(object({
    repository = string
    tag        = string
    digest     = string
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for k in keys(var.cert_manager_images) : contains(["controller", "webhook", "cainjector", "acmesolver", "startupapicheck"], k)])
    error_message = "cert_manager_images keys must be among: controller, webhook, cainjector, acmesolver, startupapicheck."
  }

  validation {
    condition     = alltrue([for v in values(var.cert_manager_images) : can(regex("^sha256:[0-9a-f]{64}$", v.digest))])
    error_message = "cert_manager_images: every entry needs a digest of the form sha256:<64 lowercase hex characters>; tag-only image overrides are refused."
  }

  validation {
    condition     = alltrue([for v in values(var.cert_manager_images) : can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?(/[a-z0-9._-]+)+$", v.repository))])
    error_message = "cert_manager_images: repository must be a registry host (optional port) and path such as 10.0.0.1/proj/image, without a scheme, tag or digest."
  }

  validation {
    condition     = alltrue([for v in values(var.cert_manager_images) : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", v.tag))])
    error_message = "cert_manager_images: tag must be a valid image tag (the chart renders it with the digest)."
  }
}
