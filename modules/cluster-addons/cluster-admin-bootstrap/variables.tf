variable "chart_path" {
  type        = string
  description = "Path to the committed, engine-generated cluster-admin chart directory (bootstrap/cluster-admin/). Must contain Chart.yaml."

  validation {
    condition     = fileexists("${var.chart_path}/Chart.yaml")
    error_message = "chart_path must be a chart directory containing Chart.yaml."
  }
}

variable "apply_via" {
  type        = string
  description = "How the chart reaches the cluster: `in-vnet` (helm provider, the admin's machine reaches the API server) or `run-command` (AKS run-command, for a private cluster). Required; the module never falls back from one to the other."

  validation {
    condition     = contains(["in-vnet", "run-command"], var.apply_via)
    error_message = "apply_via must be \"in-vnet\" or \"run-command\"."
  }
}

variable "release_name" {
  type        = string
  description = "Helm release name. A DNS label: it is placed in a shell command for run-command."
  default     = "xema-cluster-admin-bootstrap"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,51}[a-z0-9])?$", var.release_name))
    error_message = "release_name must be a DNS label (lowercase alphanumerics and '-', at most 53 characters)."
  }
}

variable "release_namespace" {
  type        = string
  description = "Namespace holding the Helm release record (a Secret). It must NOT be a namespace the deployer can write: Helm trusts the release Secret, so a forged one would make Helm delete objects with cluster-admin rights."
  default     = "xema-cluster-admin"

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$", var.release_namespace))
    error_message = "release_namespace must be a DNS label (lowercase alphanumerics and '-', at most 63 characters)."
  }
}

variable "aks_cluster_id" {
  type        = string
  description = "Resource id of the AKS managed cluster that runs the command. Required when apply_via = run-command."
  default     = null

  validation {
    condition     = var.apply_via != "run-command" || (var.aks_cluster_id != null && var.aks_cluster_id != "")
    error_message = "aks_cluster_id is required when apply_via = \"run-command\"."
  }
}

variable "chart_archive_path" {
  type        = string
  description = "Where run-command writes the zip of chart_path before sending it. Null uses a file inside this module's directory. Must not be inside chart_path."
  default     = null

  validation {
    condition     = var.chart_archive_path == null || !startswith(abspath(var.chart_archive_path), "${abspath(var.chart_path)}/")
    error_message = "chart_archive_path must not be inside chart_path (the zip would include itself)."
  }
}

variable "cluster_token" {
  type        = string
  description = "The admin's Entra access token for the AKS server app, sent as clusterToken so the run-command pod acts as the admin. Required when apply_via = run-command; not used in in-vnet mode. Set it from the environment, never a tfvars file."
  default     = null
  sensitive   = true
  ephemeral   = true

  validation {
    condition     = var.apply_via != "run-command" || (var.cluster_token != null && var.cluster_token != "")
    error_message = "cluster_token is required when apply_via = \"run-command\". Get it with: az account get-access-token --resource 6dae42f8-4368-4678-94ff-3960e28e3630 --query accessToken -o tsv, and export it as TF_VAR_cluster_token."
  }
}
