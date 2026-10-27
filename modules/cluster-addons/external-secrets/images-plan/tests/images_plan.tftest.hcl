# Provider-free: the image-override rules of cluster-addons/external-secrets and the values
# they render to, proven at plan on Terraform 1.6 and OpenTofu alike.

run "empty_overrides_render_no_values" {
  command = plan
  assert {
    condition     = length(output.values) == 0
    error_message = "no image overrides must add no values document, so existing consumers plan no change."
  }
}

run "digest_override_renders_tag_at_digest" {
  command = plan
  variables {
    images = {
      controller      = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
      webhook         = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
      cert_controller = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    }
  }
  assert {
    condition = output.values[0] == yamlencode({
      image          = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
      webhook        = { image = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
      certController = { image = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
    })
    error_message = "each component renders repository plus tag@digest under its chart key."
  }
}

run "tag_only_override_is_refused" {
  command = plan
  variables {
    images = { controller = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0", digest = "" } }
  }
  expect_failures = [var.images]
}

run "unknown_key_is_refused" {
  command = plan
  variables {
    images = { operator = { repository = "10.0.0.1/eso/external-secrets", tag = "v2.10.0", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  }
  expect_failures = [var.images]
}

run "repository_with_tag_is_refused" {
  command = plan
  variables {
    images = { controller = { repository = "10.0.0.1/eso/external-secrets:v2.10.0", tag = "v2.10.0", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  }
  expect_failures = [var.images]
}
