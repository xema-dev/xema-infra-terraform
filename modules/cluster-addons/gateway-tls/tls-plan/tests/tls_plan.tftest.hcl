# Every input-combination invariant of cluster-addons/gateway-tls, at plan time, with no provider.
variables {
  gateway_implementation = "nginx-gateway-fabric"
  gateway_name           = "gateway"
  route_namespaces       = ["apps"]
  cluster_issuer_name    = "letsencrypt"
  acme_email             = "ops@example.test"
  tls_solver             = "http01"
  listeners = {
    app = { hostname = "app.example.com", certificate_mode = "managed" }
    shop = {
      hostname         = "shop.example.org"
      certificate_mode = "customer_supplied"
      secret_name      = "shop-example-org-tls"
    }
  }
}

run "many_hosts_many_apexes" {
  command = plan
  assert {
    condition     = length(output.listeners) == 2 && output.listeners["app"].hostname == "app.example.com" && output.listeners["shop"].hostname == "shop.example.org"
    error_message = "one listener per hostname, across apex domains."
  }
  assert {
    condition     = output.listeners["app"].secret_name == "gateway-app-tls" && output.listeners["shop"].secret_name == "shop-example-org-tls"
    error_message = "a managed listener gets the module-named Secret; a customer_supplied one keeps the customer's."
  }
}

run "customer_supplied_issues_nothing" {
  command = plan
  assert {
    condition     = join(",", keys(output.certificates)) == "app"
    error_message = "only managed listeners get a Certificate."
  }
  assert {
    condition     = output.certificates["app"].dns_names == ["app.example.com"] && output.certificates["app"].secret_name == "gateway-app-tls" && output.certificates["app"].issuer_name == "letsencrypt" && output.certificates["app"].name == "gateway-app"
    error_message = "a managed Certificate covers exactly its listener's hostname, into its listener's Secret, from the ClusterIssuer."
  }
}

run "all_customer_supplied" {
  command = plan
  variables {
    acme_email = null
    tls_solver = null
    listeners = {
      a = { hostname = "*.example.com", certificate_mode = "customer_supplied", secret_name = "wildcard" }
      b = { hostname = "example.net", certificate_mode = "customer_supplied", secret_name = "wildcard" }
    }
  }
  assert {
    condition     = length(output.certificates) == 0 && output.listeners["a"].secret_name == "wildcard" && output.listeners["b"].secret_name == "wildcard"
    error_message = "customer_supplied listeners issue nothing, even a wildcard, and may share one Secret."
  }
  assert {
    condition     = output.issuer == false
    error_message = "with every listener customer_supplied no issuer (and no cert-manager) is installed."
  }
}

run "no_listener_refused" {
  command = plan
  variables {
    listeners = {}
  }
  expect_failures = [terraform_data.guard]
}

run "duplicate_hostname_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "app.example.com", certificate_mode = "managed" }
      b = { hostname = "app.example.com", certificate_mode = "customer_supplied", secret_name = "s" }
    }
  }
  expect_failures = [var.listeners]
}

run "customer_supplied_without_secret_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "app.example.com", certificate_mode = "customer_supplied" }
    }
  }
  expect_failures = [var.listeners]
}

run "customer_supplied_invalid_secret_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "app.example.com", certificate_mode = "customer_supplied", secret_name = "Not_A_Name" }
    }
  }
  expect_failures = [var.listeners]
}

run "managed_with_secret_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "app.example.com", certificate_mode = "managed", secret_name = "mine" }
    }
  }
  expect_failures = [var.listeners]
}

run "unknown_certificate_mode_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "app.example.com", certificate_mode = "self-signed" }
    }
  }
  expect_failures = [var.listeners]
}

run "reserved_listener_name_refused" {
  command = plan
  variables {
    listeners = {
      http = { hostname = "app.example.com", certificate_mode = "managed" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "invalid_listener_name_refused" {
  command = plan
  variables {
    listeners = {
      "App_1" = { hostname = "app.example.com", certificate_mode = "managed" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "invalid_hostname_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "App.Example.com", certificate_mode = "managed" }
    }
  }
  expect_failures = [var.listeners]
}

run "bare_label_hostname_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "localhost", certificate_mode = "managed" }
    }
  }
  expect_failures = [var.listeners]
}

run "too_many_listeners_refused" {
  command = plan
  variables {
    # 64 HTTPS listeners: one over the Gateway's 64 with the port-80 listener.
    listeners = {
      l00 = { hostname = "h00.example.com", certificate_mode = "managed" }
      l01 = { hostname = "h01.example.com", certificate_mode = "managed" }
      l02 = { hostname = "h02.example.com", certificate_mode = "managed" }
      l03 = { hostname = "h03.example.com", certificate_mode = "managed" }
      l04 = { hostname = "h04.example.com", certificate_mode = "managed" }
      l05 = { hostname = "h05.example.com", certificate_mode = "managed" }
      l06 = { hostname = "h06.example.com", certificate_mode = "managed" }
      l07 = { hostname = "h07.example.com", certificate_mode = "managed" }
      l08 = { hostname = "h08.example.com", certificate_mode = "managed" }
      l09 = { hostname = "h09.example.com", certificate_mode = "managed" }
      l10 = { hostname = "h10.example.com", certificate_mode = "managed" }
      l11 = { hostname = "h11.example.com", certificate_mode = "managed" }
      l12 = { hostname = "h12.example.com", certificate_mode = "managed" }
      l13 = { hostname = "h13.example.com", certificate_mode = "managed" }
      l14 = { hostname = "h14.example.com", certificate_mode = "managed" }
      l15 = { hostname = "h15.example.com", certificate_mode = "managed" }
      l16 = { hostname = "h16.example.com", certificate_mode = "managed" }
      l17 = { hostname = "h17.example.com", certificate_mode = "managed" }
      l18 = { hostname = "h18.example.com", certificate_mode = "managed" }
      l19 = { hostname = "h19.example.com", certificate_mode = "managed" }
      l20 = { hostname = "h20.example.com", certificate_mode = "managed" }
      l21 = { hostname = "h21.example.com", certificate_mode = "managed" }
      l22 = { hostname = "h22.example.com", certificate_mode = "managed" }
      l23 = { hostname = "h23.example.com", certificate_mode = "managed" }
      l24 = { hostname = "h24.example.com", certificate_mode = "managed" }
      l25 = { hostname = "h25.example.com", certificate_mode = "managed" }
      l26 = { hostname = "h26.example.com", certificate_mode = "managed" }
      l27 = { hostname = "h27.example.com", certificate_mode = "managed" }
      l28 = { hostname = "h28.example.com", certificate_mode = "managed" }
      l29 = { hostname = "h29.example.com", certificate_mode = "managed" }
      l30 = { hostname = "h30.example.com", certificate_mode = "managed" }
      l31 = { hostname = "h31.example.com", certificate_mode = "managed" }
      l32 = { hostname = "h32.example.com", certificate_mode = "managed" }
      l33 = { hostname = "h33.example.com", certificate_mode = "managed" }
      l34 = { hostname = "h34.example.com", certificate_mode = "managed" }
      l35 = { hostname = "h35.example.com", certificate_mode = "managed" }
      l36 = { hostname = "h36.example.com", certificate_mode = "managed" }
      l37 = { hostname = "h37.example.com", certificate_mode = "managed" }
      l38 = { hostname = "h38.example.com", certificate_mode = "managed" }
      l39 = { hostname = "h39.example.com", certificate_mode = "managed" }
      l40 = { hostname = "h40.example.com", certificate_mode = "managed" }
      l41 = { hostname = "h41.example.com", certificate_mode = "managed" }
      l42 = { hostname = "h42.example.com", certificate_mode = "managed" }
      l43 = { hostname = "h43.example.com", certificate_mode = "managed" }
      l44 = { hostname = "h44.example.com", certificate_mode = "managed" }
      l45 = { hostname = "h45.example.com", certificate_mode = "managed" }
      l46 = { hostname = "h46.example.com", certificate_mode = "managed" }
      l47 = { hostname = "h47.example.com", certificate_mode = "managed" }
      l48 = { hostname = "h48.example.com", certificate_mode = "managed" }
      l49 = { hostname = "h49.example.com", certificate_mode = "managed" }
      l50 = { hostname = "h50.example.com", certificate_mode = "managed" }
      l51 = { hostname = "h51.example.com", certificate_mode = "managed" }
      l52 = { hostname = "h52.example.com", certificate_mode = "managed" }
      l53 = { hostname = "h53.example.com", certificate_mode = "managed" }
      l54 = { hostname = "h54.example.com", certificate_mode = "managed" }
      l55 = { hostname = "h55.example.com", certificate_mode = "managed" }
      l56 = { hostname = "h56.example.com", certificate_mode = "managed" }
      l57 = { hostname = "h57.example.com", certificate_mode = "managed" }
      l58 = { hostname = "h58.example.com", certificate_mode = "managed" }
      l59 = { hostname = "h59.example.com", certificate_mode = "managed" }
      l60 = { hostname = "h60.example.com", certificate_mode = "managed" }
      l61 = { hostname = "h61.example.com", certificate_mode = "managed" }
      l62 = { hostname = "h62.example.com", certificate_mode = "managed" }
      l63 = { hostname = "h63.example.com", certificate_mode = "managed" }
    }
  }
  expect_failures = [var.listeners]
}

run "managed_wildcard_with_http01_refused" {
  command = plan
  variables {
    listeners = {
      a = { hostname = "*.example.com", certificate_mode = "managed" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "managed_wildcard_with_dns01_in_zone" {
  command = plan
  variables {
    tls_solver  = "dns01-azure"
    dns01_zones = ["example.com"]
    listeners = {
      wild = { hostname = "*.example.com", certificate_mode = "managed" }
      apex = { hostname = "example.com", certificate_mode = "managed" }
      deep = { hostname = "a.b.example.com", certificate_mode = "managed" }
      other = {
        hostname         = "example.org"
        certificate_mode = "customer_supplied"
        secret_name      = "example-org"
      }
    }
  }
  assert {
    condition     = join(",", sort(keys(output.certificates))) == "apex,deep,wild"
    error_message = "dns01-azure issues every managed hostname in its zone; a hostname outside it may be customer_supplied."
  }
}

run "managed_outside_dns01_zone_refused" {
  command = plan
  variables {
    tls_solver  = "dns01-azure"
    dns01_zones = ["example.com"]
    listeners = {
      a = { hostname = "app.notexample.com", certificate_mode = "managed" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "dns01_without_zone_refused" {
  command = plan
  variables {
    tls_solver = "dns01-azure"
    listeners = {
      a = { hostname = "app.example.com", certificate_mode = "managed" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "customer_secret_colliding_with_managed_refused" {
  command = plan
  variables {
    listeners = {
      app = { hostname = "app.example.com", certificate_mode = "managed" }
      b = {
        hostname         = "b.example.com"
        certificate_mode = "customer_supplied"
        secret_name      = "gateway-app-tls"
      }
    }
  }
  expect_failures = [terraform_data.guard]
}

# The two-apex shape: one Gateway, an apex and a second apex below it, each a wildcard listener.
run "two_wildcard_apexes_managed_by_dns01_zones" {
  command = plan
  variables {
    tls_solver  = "dns01-azure"
    dns01_zones = ["example.test", "dev.example.test"]
    listeners = {
      prod = { hostname = "*.example.test", certificate_mode = "managed" }
      dev  = { hostname = "*.dev.example.test", certificate_mode = "managed" }
    }
  }
  assert {
    condition     = output.certificates["prod"].dns_names == ["*.example.test"] && output.certificates["dev"].dns_names == ["*.dev.example.test"]
    error_message = "each wildcard apex gets its own Certificate covering exactly its listener's hostname."
  }
  assert {
    condition     = output.listeners["prod"].secret_name == "gateway-prod-tls" && output.listeners["dev"].secret_name == "gateway-dev-tls"
    error_message = "each listener terminates TLS with its own Secret."
  }
}

run "two_wildcard_apexes_one_managed_one_customer_supplied" {
  command = plan
  variables {
    tls_solver  = "dns01-azure"
    dns01_zones = ["example.test"]
    listeners = {
      prod = {
        hostname         = "*.example.test"
        certificate_mode = "customer_supplied"
        secret_name      = "example-test-wildcard"
      }
      dev = { hostname = "*.dev.example.test", certificate_mode = "managed" }
    }
  }
  assert {
    condition     = join(",", keys(output.certificates)) == "dev" && output.listeners["prod"].secret_name == "example-test-wildcard"
    error_message = "the customer_supplied apex issues nothing; the managed one issues from the zone it sits in."
  }
  assert {
    condition     = output.issuer == true
    error_message = "a mixed Gateway installs the issuer for its managed listener."
  }
}

run "two_wildcard_apexes_customer_supplied" {
  command = plan
  variables {
    acme_email = null
    tls_solver = null
    listeners = {
      prod = {
        hostname         = "*.example.test"
        certificate_mode = "customer_supplied"
        secret_name      = "example-test-wildcard"
      }
      dev = {
        hostname         = "*.dev.example.test"
        certificate_mode = "customer_supplied"
        secret_name      = "dev-example-test-wildcard"
      }
    }
  }
  assert {
    condition     = length(output.certificates) == 0 && output.listeners["dev"].secret_name == "dev-example-test-wildcard"
    error_message = "two customer_supplied wildcard apexes need no DNS-01 solver and issue nothing."
  }
  assert {
    condition     = output.issuer == false
    error_message = "no managed listener: no issuer, no ACME account, no solver."
  }
}

run "two_wildcard_apexes_second_zone_missing_refused" {
  command = plan
  variables {
    tls_solver  = "dns01-azure"
    dns01_zones = ["dev.example.test"]
    listeners = {
      prod = { hostname = "*.example.test", certificate_mode = "managed" }
      dev  = { hostname = "*.dev.example.test", certificate_mode = "managed" }
    }
  }
  expect_failures = [terraform_data.guard]
}

# --- whether an issuer exists: only for something to issue -------------------------------------

run "mixed_listeners_install_the_issuer" {
  command = plan
  assert {
    condition     = output.issuer == true && join(",", keys(output.certificates)) == "app"
    error_message = "one managed listener among customer_supplied ones installs the issuer and issues only its own Certificate."
  }
}

run "customer_supplied_only_with_acme_email_refused" {
  command = plan
  variables {
    tls_solver = null
    listeners = {
      a = { hostname = "*.example.test", certificate_mode = "customer_supplied", secret_name = "s" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "customer_supplied_only_with_solver_refused" {
  command = plan
  variables {
    acme_email = null
    listeners = {
      a = { hostname = "*.example.test", certificate_mode = "customer_supplied", secret_name = "s" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "customer_supplied_only_with_dns01_zones_refused" {
  command = plan
  variables {
    acme_email  = null
    tls_solver  = null
    dns01_zones = ["example.test"]
    listeners = {
      a = { hostname = "*.example.test", certificate_mode = "customer_supplied", secret_name = "s" }
    }
  }
  expect_failures = [terraform_data.guard]
}

run "managed_without_acme_email_refused" {
  command = plan
  variables {
    acme_email = null
  }
  expect_failures = [terraform_data.guard]
}

run "managed_without_solver_refused" {
  command = plan
  variables {
    tls_solver = null
  }
  expect_failures = [terraform_data.guard]
}

run "unknown_solver_refused" {
  command = plan
  variables {
    tls_solver = "dns01-route53"
  }
  expect_failures = [var.tls_solver]
}

run "dns01_zones_without_dns01_refused" {
  command = plan
  variables {
    dns01_zones = ["example.com"]
  }
  expect_failures = [terraform_data.guard]
}

# --- gateway implementation --------------------------------------------------------------------

run "customer_managed_gateway_installs_the_issuer" {
  command = plan
  variables {
    gateway_implementation               = "customer-managed"
    customer_gateway_https_section_names = ["https"]
    route_namespaces                     = []
    listeners                            = {}
  }
  assert {
    condition     = output.issuer == true && length(output.listeners) == 0 && length(output.certificates) == 0
    error_message = "a customer-managed Gateway gets the issuer and no module-owned listener."
  }
}

run "customer_managed_without_acme_email_refused" {
  command = plan
  variables {
    gateway_implementation               = "customer-managed"
    customer_gateway_https_section_names = ["https"]
    listeners                            = {}
    acme_email                           = null
  }
  expect_failures = [terraform_data.guard]
}

run "customer_managed_without_customer_gateway_refused" {
  command = plan
  variables {
    gateway_implementation = "customer-managed"
    listeners              = {}
  }
  expect_failures = [terraform_data.guard]
}

run "customer_managed_with_listeners_refused" {
  command = plan
  variables {
    gateway_implementation               = "customer-managed"
    customer_gateway_https_section_names = ["https"]
  }
  expect_failures = [terraform_data.guard]
}

run "ngf_with_customer_gateway_refused" {
  command = plan
  variables {
    customer_gateway_https_section_names = ["https"]
  }
  expect_failures = [terraform_data.guard]
}

run "ngf_without_route_namespaces_refused" {
  command = plan
  variables {
    route_namespaces = []
  }
  expect_failures = [terraform_data.guard]
}

run "unknown_gateway_implementation_refused" {
  command = plan
  variables {
    gateway_implementation = "istio"
  }
  expect_failures = [var.gateway_implementation]
}

run "customer_gateway_sections_follow_the_listener_name_rule" {
  command = plan
  variables {
    gateway_implementation               = "customer-managed"
    customer_gateway_https_section_names = ["prod", "dev-1"]
    route_namespaces                     = []
    listeners                            = {}
  }
  assert {
    condition     = output.issuer == true
    error_message = "DNS-1123-label section names are accepted."
  }
}

run "customer_gateway_section_http_refused" {
  command = plan
  variables {
    gateway_implementation               = "customer-managed"
    customer_gateway_https_section_names = ["https", "http"]
    listeners                            = {}
  }
  expect_failures = [terraform_data.guard]
}

run "customer_gateway_section_invalid_name_refused" {
  command = plan
  variables {
    gateway_implementation               = "customer-managed"
    customer_gateway_https_section_names = ["Prod_1"]
    listeners                            = {}
  }
  expect_failures = [terraform_data.guard]
}
