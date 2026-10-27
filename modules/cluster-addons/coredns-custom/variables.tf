variable "zones" {
  description = "DNS zones CoreDNS forwards to the forwarder, one server block each (validated by ./server-blocks). Empty creates nothing."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "forwarder" {
  description = "Resolver the zones are forwarded to. The default is Azure DNS (168.63.129.16)."
  type        = string
  default     = "168.63.129.16"
}
