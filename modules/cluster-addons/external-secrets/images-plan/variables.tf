variable "images" {
  description = <<-EOT
    Image overrides for the three External Secrets Operator images, keyed by component (`controller`, `webhook`, `cert_controller`); empty (the default) keeps the chart's own images.
    Each entry sets the full image repository (registry host and path, no tag or digest), a tag, and a REQUIRED
    sha256 digest, so a registry override can never be tags-only. Rendered into the chart as image.repository / image.tag (the chart has no digest key, so the tag value is `<tag>@<digest>`), webhook.image.* and certController.image.*. Leave the chart's `flavour` unset.
  EOT
  type = map(object({
    repository = string
    tag        = string
    digest     = string
  }))
  nullable = false
  default  = {}

  validation {
    condition     = alltrue([for k in keys(var.images) : contains(["controller", "webhook", "cert_controller"], k)])
    error_message = "images keys must be among: controller, webhook, cert_controller."
  }

  validation {
    condition     = alltrue([for v in values(var.images) : can(regex("^sha256:[0-9a-f]{64}$", v.digest))])
    error_message = "images: every entry needs a digest of the form sha256:<64 lowercase hex characters>; tag-only image overrides are refused."
  }

  validation {
    condition     = alltrue([for v in values(var.images) : can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*(:[0-9]+)?(/[a-z0-9._-]+)+$", v.repository))])
    error_message = "images: repository must be a registry host (optional port) and path such as 10.0.0.1/proj/image, without a scheme, tag or digest."
  }

  validation {
    condition     = alltrue([for v in values(var.images) : can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", v.tag))])
    error_message = "images: tag must be a valid image tag (it is rendered as <tag>@<digest>)."
  }
}
