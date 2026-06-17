variable "domain" {
  description = "Managed zone apex (e.g. \"xema.dev\")."
  type        = string
}

variable "records" {
  description = <<-EOT
    DNS records keyed by a stable id. Each record:
      - name  : record name relative to the zone apex ("@" for the apex)
      - type  : record type (e.g. "A", "AAAA", "CNAME", "TXT", "MX"); default "A"
      - value : record value. For CNAME, DO requires an FQDN with a trailing
                dot (e.g. "target.example.com.") — see README; not mutated here.
      - ttl   : time-to-live in seconds; default 300
  EOT
  type = map(object({
    name  = string
    type  = optional(string, "A")
    value = string
    ttl   = optional(number, 300)
  }))
  default = {}

  validation {
    condition = alltrue([
      for r in values(var.records) :
      contains(["A", "AAAA", "CNAME", "TXT", "MX", "NS", "SRV", "CAA", "SOA"], r.type)
    ])
    error_message = "record type must be one of A, AAAA, CNAME, TXT, MX, NS, SRV, CAA, SOA."
  }
}
