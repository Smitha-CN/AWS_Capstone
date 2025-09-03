variable "region" {
  description = "AWS region where resources will be deployed"
  default     = "us-east-1"
}

variable "db_username" {
  description = "Database username"
  default     = "admin"
}

variable "db_password" {
  description = "Database password"
  default     = "adminadmin"
  sensitive   = true
}

