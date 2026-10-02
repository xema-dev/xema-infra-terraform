terraform {
  required_version = ">= 1.6"
  required_providers {
    postgresql = {
      source = "cyrilgdn/postgresql"
      # 1.24 is a MEASURED floor, not a habit. Against PostgreSQL 16 as a
      # non-superuser: 1.22, even with the membership main.tf grants, cannot
      # DROP a role it created (`could not reassign owned by role … permission
      # denied to reassign objects`); 1.23 failed the same CREATE DATABASE as
      # 1.22 without that membership and was not re-measured with it. 1.24 and
      # 1.27 apply, plan empty and destroy clean.
      version = ">= 1.24"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}
