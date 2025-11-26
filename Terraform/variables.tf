variable "prefix" {
  default     = "Corp-Lon"
  description = "Default prefix for all resources"
  type        = string
}

variable "Location" {
  default     = "uksouth"
  description = "Default location for all resources"
  type        = string
}

variable "AuthMainSubscription" {
  type = map(string)
  default = {
    client_id       = "47d9efd4-b778-4dfa-bda6-61c7e3c8485e"
    client_secret   = "jp_8Q~07DJ6iJh33EQBDJ~y.0DbpnBxxd4gy9cc3"
    tenant_id       = "c2efc329-9485-4475-bdc6-267f4b9954ef"
    subscription_id = "7d5c31a8-13f6-43df-94ea-0c8a29822457"
  }
}

variable "FreeTrialSubscription" {
  type = map(string)
  default = {
    client_id       = "47d9efd4-b778-4dfa-bda6-61c7e3c8485e"
    client_secret   = "jp_8Q~07DJ6iJh33EQBDJ~y.0DbpnBxxd4gy9cc3"
    tenant_id       = "aa87ffb6-96b8-49b8-afef-4e8a5eee164d"
    subscription_id = "7d5c31a8-13f6-43df-94ea-0c8a29822457"
  }
}