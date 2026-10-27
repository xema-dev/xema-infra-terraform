# Provider-free: the image-override rules of cluster-addons/gateway-tls and the values they
# render to, proven at plan on Terraform 1.6 and OpenTofu alike.

run "empty_overrides_render_no_values" {
  command = plan
  assert {
    condition     = length(output.ngf_values) == 0 && length(output.cert_manager_values) == 0
    error_message = "no image overrides must add no values document, so existing consumers plan no change."
  }
}

run "ngf_override_renders_tag_at_digest" {
  command = plan
  variables {
    ngf_images = {
      controller = { repository = "10.0.0.1/ngf/nginx-gateway-fabric", tag = "2.7.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
      nginx      = { repository = "10.0.0.1/ngf/nginx", tag = "2.7.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    }
  }
  assert {
    condition = output.ngf_values[0] == yamlencode({
      nginxGateway = { image = { repository = "10.0.0.1/ngf/nginx-gateway-fabric", tag = "2.7.2@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
      nginx        = { image = { repository = "10.0.0.1/ngf/nginx", tag = "2.7.2@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
    })
    error_message = "NGF has no digest key, so the tag carries tag@digest."
  }
}

run "cert_manager_override_uses_the_digest_key" {
  command = plan
  variables {
    cert_manager_images = {
      controller = { repository = "10.0.0.1/cm/controller", tag = "v1.21.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
      webhook    = { repository = "10.0.0.1/cm/webhook", tag = "v1.21.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
    }
  }
  assert {
    condition = output.cert_manager_values[0] == yamlencode({
      image   = { repository = "10.0.0.1/cm/controller", tag = "v1.21.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
      webhook = { image = { repository = "10.0.0.1/cm/webhook", tag = "v1.21.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
    })
    error_message = "cert-manager renders repository, tag and digest separately."
  }
}

run "ngf_tag_only_override_is_refused" {
  command = plan
  variables {
    ngf_images = { controller = { repository = "10.0.0.1/ngf/nginx-gateway-fabric", tag = "2.7.2", digest = "" } }
  }
  expect_failures = [var.ngf_images]
}

run "cert_manager_tag_only_override_is_refused" {
  command = plan
  variables {
    cert_manager_images = { controller = { repository = "10.0.0.1/cm/controller", tag = "v1.21.2", digest = "" } }
  }
  expect_failures = [var.cert_manager_images]
}

run "unknown_key_is_refused" {
  command = plan
  variables {
    ngf_images          = { operator = { repository = "10.0.0.1/ngf/x", tag = "2.7.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
    cert_manager_images = { operator = { repository = "10.0.0.1/cm/x", tag = "v1.21.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  }
  expect_failures = [var.ngf_images, var.cert_manager_images]
}

run "repository_with_tag_is_refused" {
  command = plan
  variables {
    ngf_images          = { controller = { repository = "10.0.0.1/ngf/x:2.7.2", tag = "2.7.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
    cert_manager_images = { controller = { repository = "10.0.0.1/cm/x:v1.21.2", tag = "v1.21.2", digest = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" } }
  }
  expect_failures = [var.ngf_images, var.cert_manager_images]
}
