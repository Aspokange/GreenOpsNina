variable "key_name" {
  description = "Nom de la clé SSH AWS"
  type        = string
}

variable "db_password" {
  description = "Mot de passe de la base RDS"
  type        = string
  sensitive   = true
}