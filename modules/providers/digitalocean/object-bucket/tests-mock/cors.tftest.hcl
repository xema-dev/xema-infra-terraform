# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# cors_rules is opt-in: no CORS configuration resource by default; the rules map onto
# digitalocean_spaces_bucket_cors_configuration.

mock_provider "digitalocean" {}

variables {
  name   = "xema-test-bucket"
  region = "fra1"
}

run "default_renders_no_cors" {
  command = plan

  assert {
    condition     = length(digitalocean_spaces_bucket_cors_configuration.this) == 0
    error_message = "without cors_rules no CORS configuration resource exists."
  }
}

run "rule_maps_every_field" {
  command = plan

  variables {
    cors_rules = [{
      allowed_origins = ["https://app.example.com"]
      allowed_methods = ["GET", "PUT"]
      allowed_headers = ["*"]
      exposed_headers = ["ETag"]
      max_age         = 3600
    }]
  }

  assert {
    condition = (
      length(digitalocean_spaces_bucket_cors_configuration.this) == 1
      && length(digitalocean_spaces_bucket_cors_configuration.this[0].cors_rule) == 1
      && [for r in digitalocean_spaces_bucket_cors_configuration.this[0].cors_rule : toset(r.allowed_origins)][0] == toset(["https://app.example.com"])
      && [for r in digitalocean_spaces_bucket_cors_configuration.this[0].cors_rule : toset(r.allowed_methods)][0] == toset(["GET", "PUT"])
      && [for r in digitalocean_spaces_bucket_cors_configuration.this[0].cors_rule : toset(r.allowed_headers)][0] == toset(["*"])
      && [for r in digitalocean_spaces_bucket_cors_configuration.this[0].cors_rule : toset(r.expose_headers)][0] == toset(["ETag"])
      && [for r in digitalocean_spaces_bucket_cors_configuration.this[0].cors_rule : r.max_age_seconds][0] == 3600
    )
    error_message = "the rule maps origins, methods, headers, exposed headers and max age."
  }
}

run "origin_with_path_fails" {
  command = plan

  variables {
    cors_rules = [{
      allowed_origins = ["https://app.example.com/path"]
      allowed_methods = ["GET"]
    }]
  }

  expect_failures = [var.cors_rules]
}

run "method_outside_set_fails" {
  command = plan

  variables {
    cors_rules = [{
      allowed_origins = ["*"]
      allowed_methods = ["PATCH"]
    }]
  }

  expect_failures = [var.cors_rules]
}
