variable "name" {
  description = "Database cluster name."
  type        = string
}

variable "region" {
  description = "DigitalOcean region slug (e.g. \"fra1\")."
  type        = string
}

variable "engine_version" {
  description = "Major Postgres version (e.g. \"16\"). Maps to digitalocean_database_cluster.version."
  type        = string
}

variable "size" {
  description = "DO managed-database size slug (e.g. \"db-s-1vcpu-2gb\")."
  type        = string
}

variable "node_count" {
  description = "Node count (1 = single node, 2+ = primary plus standby replicas)."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count >= 1
    error_message = "node_count must be >= 1."
  }
}

variable "vpc_id" {
  description = "Existing VPC uuid to attach the cluster to for private networking. Empty string lets DO pick the region default VPC."
  type        = string
  default     = ""
}

variable "databases" {
  description = "Logical databases to ensure exist on the cluster."
  type        = set(string)
  default     = []
}

variable "roles" {
  description = "Logical roles/users to ensure exist on the cluster."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to the cluster. Rendered to DO's flat tag list as \"key:value\"."
  type        = map(string)
  default     = {}
}
