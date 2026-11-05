# Needs mock_provider (OpenTofu 1.8+, Terraform 1.7+): run as
#   tofu test -test-directory=tests-mock
#
# Each database owner gets CREATE and USAGE on its own database's public schema,
# since on Azure Flexible Server ownership of the database does not carry them.
# A role that owns nothing gets no schema grant.

mock_provider "postgresql" {}
mock_provider "random" {}

variables {
  connecting_role = "admin"
  databases       = ["app_a", "shared"]
  roles           = ["app_a", "reader"]
  database_owners = { app_a = "app_a" }
  connect_grants  = { app_a = ["app_a"], reader = ["app_a", "shared"] }
}

run "owner_gets_create_on_public_only_in_its_database" {
  command = plan

  assert {
    condition     = keys(postgresql_grant.owner_public_schema) == ["app_a"]
    error_message = "only a database with an owner gets the schema grant."
  }

  assert {
    condition = (
      postgresql_grant.owner_public_schema["app_a"].schema == "public"
      && postgresql_grant.owner_public_schema["app_a"].object_type == "schema"
      && postgresql_grant.owner_public_schema["app_a"].role == "app_a"
      && toset(postgresql_grant.owner_public_schema["app_a"].privileges) == toset(["CREATE", "USAGE"])
    )
    error_message = "the owner must hold CREATE and USAGE on public."
  }
}
