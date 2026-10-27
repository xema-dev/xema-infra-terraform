# The Helm values the image overrides render to, with no provider. Empty overrides render no
# values document, so a root that sets none plans no change.
locals {
  # NGINX Gateway Fabric has no digest key: the tag value carries "<tag>@<digest>" and the chart
  # renders repository:tag.
  ngf_values = length(var.ngf_images) == 0 ? [] : [yamlencode({
    for k, v in var.ngf_images : (k == "controller" ? "nginxGateway" : "nginx") => {
      image = { repository = v.repository, tag = "${v.tag}@${v.digest}" }
    }
  })]

  # cert-manager takes repository, tag and digest separately; the controller's image is top-level.
  cert_manager_values = length(var.cert_manager_images) == 0 ? [] : [yamlencode(merge(
    { for k, v in var.cert_manager_images : "image" => { repository = v.repository, tag = v.tag, digest = v.digest } if k == "controller" },
    { for k, v in var.cert_manager_images : k => {
      image = { repository = v.repository, tag = v.tag, digest = v.digest }
    } if k != "controller" },
  ))]
}
