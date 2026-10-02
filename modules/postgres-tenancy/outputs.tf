output "databases" {
  description = "The databases governed on the server: the ones created here and the existing_databases granted on."
  value       = toset(values(local.database_names))
}

output "roles" {
  description = "The login roles ensured on the server."
  value       = toset([for role in postgresql_role.this : role.name])
}

output "role_passwords" {
  description = <<-EOT
    The generated password per role. A credential: route it into the secret
    store the deployment reads (`terraform output -json role_passwords`), never
    into a repository. Rotation is `taint` on the role's `random_password`
    followed by an apply.
  EOT
  value       = { for name, password in random_password.role : name => password.result }
  sensitive   = true
}

output "extensions" {
  description = "The extensions ensured, as `database => set(extension)` — the answer to \"does this database carry what its application needs\" without a psql session."
  value = {
    for database in local.governed_databases : database => toset([
      for entry in postgresql_extension.this : entry.name if entry.database == database
    ])
    if length(try(var.extensions[database], [])) > 0
  }
}
