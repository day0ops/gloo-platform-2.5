variable "owner" {
  description = "Name of the maintainer of the cluster"
  type        = string
}

variable "region" {
  description = "AWS region for EKS (Ref: https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.RegionsAndAvailabilityZones.html)"
  type        = string
}

variable "max_availability_zones" {
  description = "Maximum number of availability zones used for provisioning (Default: `3`)"
  type        = number
  default     = 3
}

variable "public_subnet_ipv6_prefixes" {
  description = "Assigns IPv6 public subnet id based on the Amazon provided /56 prefix base 10 integer (0-256)"
  type        = list(string)
  default     = [0, 1]
}

variable "private_subnet_ipv6_prefixes" {
  description = "Assigns IPv6 private subnet id based on the Amazon provided /56 prefix base 10 integer (0-256)"
  type        = list(string)
  default     = [2, 3]
}

variable "create_cni_ipv6_iam_policy" {
  description = "Determines whether to create an [`AmazonEKS_CNI_IPv6_Policy`](https://docs.aws.amazon.com/eks/latest/userguide/cni-iam-role.html#cni-iam-role-create-ipv6-policy). Currently only a single cluster is supported to create this, https://github.com/terraform-aws-modules/terraform-aws-eks/issues/2131"
  type        = bool
  default     = false
}

variable "nodes" {
  description = "EKS Kubernetes worker nodes, desired ASG capacity (e.g. `2`)"
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "EKS Kubernetes worker nodes, minimum ASG capacity (e.g. `1`)"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "EKS Kubernetes worker nodes, maximum ASG capacity (e.g. `3`)"
  type        = number
  default     = 3
}

variable "node_type" {
  description = "AWS EC2 node instance type (Default: `t3.medium`, Ref: https://aws.amazon.com/ec2/instance-types)"
  type        = string
  default     = "t3.medium"
}

variable "kubernetes_version" {
  description = "Kubernetes version. If not specified the current stable version is used"
  type        = string
  default     = null
}

variable "allow_istio_mutation_webhook_sg" {
  description = "Allow security group for Istio mutation webhook (In other words allows Kubernetes admission controller access) (Default: `false`)"
  type        = bool
  default     = false
}

variable "ec2_ssh_key" {
  description = "SSH key name that should be used to access the worker nodes"
  type        = string
  default     = null
}

variable "enable_bastion" {
  description = "Enable bastion host in the VPC (Default: `false`)"
  type        = bool
  default     = false
}

variable "enable_dns64" {
  description = "DNS queries made to the Amazon-provided DNS Resolver in this subnet should return synthetic IPv6 addresses for IPv4-only destinations (Default: `false`)"
  type        = bool
  default     = true
}

# -- Tagging and labeling

variable "tags" {
  description = "Tags used for the EKS resources"
  type        = map(string)
  default     = {}
}
