# Provider-free: the rules a node CA trust list must satisfy, proven at plan on
# Terraform 1.6 and OpenTofu alike.

run "default_is_null" {
  command = plan
  assert {
    condition     = output.custom_ca_trust_certificates_base64 == null
    error_message = "no certificates must map to null, so existing clusters plan no change."
  }
}

run "certificates_are_trimmed_and_base64_encoded" {
  command = plan
  variables {
    certificates = [
      "-----BEGIN CERTIFICATE-----\nTUlJQkZBS0VDRVJU\n-----END CERTIFICATE-----\n",
      "\n-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
    ]
  }
  assert {
    condition = output.custom_ca_trust_certificates_base64 == [
      base64encode("-----BEGIN CERTIFICATE-----\nTUlJQkZBS0VDRVJU\n-----END CERTIFICATE-----"),
      base64encode("-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----"),
    ]
    error_message = "each PEM is trimmed and base64-encoded, in order."
  }
}

run "ten_certificates_are_allowed" {
  command = plan
  variables {
    certificates = [
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
    ]
  }
  assert {
    condition     = length(output.custom_ca_trust_certificates_base64) == 10
    error_message = "ten certificates are within the AKS limit."
  }
}

run "eleven_certificates_are_refused" {
  command = plan
  variables {
    certificates = [
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
      "-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----",
    ]
  }
  expect_failures = [var.certificates]
}

run "not_pem_is_refused" {
  command = plan
  variables {
    certificates = ["TUlJQkZBS0VDRVJU"]
  }
  expect_failures = [var.certificates]
}

run "bundle_in_one_entry_is_refused" {
  command = plan
  variables {
    certificates = ["-----BEGIN CERTIFICATE-----\nQUFB\n-----END CERTIFICATE-----\n-----BEGIN CERTIFICATE-----\nQkJC\n-----END CERTIFICATE-----"]
  }
  expect_failures = [var.certificates]
}

run "private_key_is_refused" {
  command = plan
  variables {
    certificates = ["-----BEGIN PRIVATE KEY-----\nQUFB\n-----END PRIVATE KEY-----"]
  }
  expect_failures = [var.certificates]
}

run "crlf_is_refused" {
  command = plan
  variables {
    certificates = ["-----BEGIN CERTIFICATE-----\r\nQUFB\r\n-----END CERTIFICATE-----"]
  }
  expect_failures = [var.certificates]
}
