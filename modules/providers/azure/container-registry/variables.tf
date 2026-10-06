variable "name" {
  description = "Registry name (5-50 lowercase letters and digits; globally unique as <name>.azurecr.io)."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{5,50}$", var.name))
    error_message = "name must be 5-50 lowercase letters and digits."
  }
}

variable "region" {
  description = "Azure location (e.g. \"westeurope\")."
  type        = string
}

variable "pull_principal_ids" {
  description = "Object ids of the identities granted AcrPull on the registry (e.g. the AKS kubelet identity). Keyed by a caller-chosen static label so the set of grants is known at plan time even when the ids are not. Pushing is never granted here: the consumer grants AcrPush to its own CI principal."
  type        = map(string)
  default     = {}
}

variable "resource_group_name" {
  description = "Existing resource group to create the registry in. Empty string creates a dedicated resource group named \"<name>-rg\"."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every created resource."
  type        = map(string)
  default     = {}
}
