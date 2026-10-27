# The Helm values the image overrides render to, with no provider. The chart has no digest key:
# the tag value carries "<tag>@<digest>" and the chart renders repository:tag. Empty overrides
# render no values document at all, so a root that sets none plans no change.
locals {
  values = length(var.images) == 0 ? [] : [yamlencode(merge(
    { for k, v in var.images : "image" => { repository = v.repository, tag = "${v.tag}@${v.digest}" } if k == "controller" },
    { for k, v in var.images : (k == "webhook" ? "webhook" : "certController") => {
      image = { repository = v.repository, tag = "${v.tag}@${v.digest}" }
    } if k != "controller" },
  ))]
}
