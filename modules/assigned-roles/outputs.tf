output "assigned_role_names" {
  description = "Sorted, de-duplicated Azure role definition names the enabled modules assign. Static: it never depends on state. A SUPERSET of what one apply creates (a module lists every role it can assign, whatever its inputs), which is what an ABAC allow-list needs. With manage_role_assignments = false the identity applying this stack needs NO RBAC Administrator role: these names are for the separate privileged root's condition only."
  value = sort(distinct(flatten([
    for k, roles in local.by_module : local.enabled[k] ? roles : []
  ])))
}
