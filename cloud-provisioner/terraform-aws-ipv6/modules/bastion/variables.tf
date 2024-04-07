variable "enable" {
  description = "Activate bastion in the VPC (Default: false)"
  type        = bool
  default     = false
}

variable "owner" {
  description = "Name of the maintainer of the cluster"
  type        = string
}

variable "prefix_name" {
  description = "Prefix name for bastion host"
  type        = string
}

variable "vpc_id" {
  description = "VPC id were the bastion will be hosted"
  type        = string
}

variable "elb_subnets" {
  description = "List of subnet were the ELB will be deployed"
  type        = list(string)
}

variable "auto_scaling_group_subnets" {
  description = "List of subnet were the Auto Scalling Group will deploy the instances"
  type        = list(string)
}

variable "bastion_ssh_key" {
  description = "SSH key name that should be used to access the bastion host"
  type        = string
  default     = null
}

# -- Tagging and labeling

variable "tags" {
  description = "Tags used for the EKS resources"
  type        = map(string)
  default     = {}
}
