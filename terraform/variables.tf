variable "pub_key" {
  type      = string
  sensitive = true
}

variable "priv_key" {
  type      = string
  sensitive = true
}

variable "db_user" {
  type      = string
  sensitive = true
}

variable "db_pass" {
  type      = string
  sensitive = true
}

variable "home" {
  type        = string
  sensitive   = true
  description = "Your public ip for ssh connection"
}

variable "db_name" {
  type      = string
  sensitive = true
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_iam_policy" "ReadOnlyAccess" {
  name = "ReadOnlyAccess"
}
