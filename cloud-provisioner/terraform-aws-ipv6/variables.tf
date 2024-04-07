# ----------------------------------------------------------------------------------
# Common properties
# ----------------------------------------------------------------------------------

variable "owner" {
  description = "Name of the maintainer of the cluster"
  type        = string

  validation {
    condition     = can(length(var.owner) > 0)
    error_message = "Maintainer of the cluster must be provided."
  }
}

variable "team" {
  description = "Team that maintains the cluster"
  type        = string
  default     = "fe-presale"
}

variable "purpose" {
  description = "Purpose for the cluster"
  type        = string
  default     = "pre-sales"
}

variable "component" {
  description = "Product type"
  type        = string
  default     = "gloo-platform"
}

variable "extra_tags" {
  description = "Tags used for the EKS resources"
  type        = map(string)
  default     = {}
}

# ----------------------------------------------------------------------------------
# AWS EKS properties
# ----------------------------------------------------------------------------------

variable "region" {
  description = "AWS region for EKS (Default: `ap-southeast-2`, Ref: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html)"
  type        = string
  default     = "ap-southeast-2"
}

variable "aws_profile" {
  description = "AWS cli profile (Default: `default`)"
  type        = string
  default     = "default"
}

variable "max_availability_zones_per_cluster" {
  description = "Maximum number of availability zones per cluster"
  type        = number
  default     = 2
}

variable "kubernetes_version" {
  description = "Kubernetes version. If not specified the current stable version is used"
  type        = string
  default     = null
}

variable "ec2_ssh_key" {
  description = "SSH key name that should be used to access the instances"
  type        = string
  default     = null
}

variable "create_cni_ipv6_iam_policy" {
  description = "Determines whether to create an [`AmazonEKS_CNI_IPv6_Policy`](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy). Currently only a single cluster is supported to create this, https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2131"
  type        = bool
  default     = false
}

# ----------------------------------------------------------------------------------
# Module properties
# ----------------------------------------------------------------------------------

variable "enable_ipv6_1" {
  description = "Enable Cluster ID #1 (Default: `true`)"
  type        = bool
  default     = true
}

variable "enable_ipv6_2" {
  description = "Enable Cluster ID #2 (Default: `true`)"
  type        = bool
  default     = true
}

variable "enable_ipv6_3" {
  description = "Enable Cluster ID #3 (Default: `true`)"
  type        = bool
  default     = true
}

variable "enable_dns64" {
  description = "DNS queries made to the Amazon-provided DNS Resolver in this subnet should return synthetic IPv6 addresses for IPv4-only destinations (Default: `true`)"
  type        = bool
  default     = true
}
