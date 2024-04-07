locals {
  tgw_name = try(format("%v-tgw", var.owner))
  tags = merge(
    {
      "created-by" = var.owner
      "team"       = var.team
      "purpose"    = var.purpose
      "component"  = var.component
      "managed-by" = "terraform"
    },
    var.extra_tags
  )
}

module "eks_ipv6_1" {
  source = "./modules/eks-ipv6"
  count  = var.enable_ipv6_1 ? 1 : 0

  owner                      = var.owner
  region                     = var.region
  max_availability_zones     = var.max_availability_zones_per_cluster
  kubernetes_version         = var.kubernetes_version
  create_cni_ipv6_iam_policy = var.create_cni_ipv6_iam_policy
  enable_dns64               = var.enable_dns64

  tags = local.tags
}

module "eks_ipv6_2" {
  source = "./modules/eks-ipv6"
  count  = var.enable_ipv6_2 ? 1 : 0

  owner                           = var.owner
  region                          = var.region
  max_availability_zones          = var.max_availability_zones_per_cluster
  kubernetes_version              = var.kubernetes_version
  allow_istio_mutation_webhook_sg = true
  ec2_ssh_key                     = var.ec2_ssh_key
  enable_bastion                  = true
  enable_dns64                    = var.enable_dns64

  tags = local.tags
}

module "eks_ipv6_3" {
  source = "./modules/eks-ipv6"
  count  = var.enable_ipv6_3 ? 1 : 0

  owner                           = var.owner
  region                          = var.region
  max_availability_zones          = var.max_availability_zones_per_cluster
  kubernetes_version              = var.kubernetes_version
  allow_istio_mutation_webhook_sg = true
  enable_dns64                    = var.enable_dns64

  tags = local.tags
}

module "tgw" {
  source  = "terraform-aws-modules/transit-gateway/aws"
  version = "~> 2.10.0"

  name = local.tgw_name

  # Only on a single account
  enable_auto_accept_shared_attachments = false

  # When "true", allows service discovery through IGMP
  enable_multicast_support = false

  enable_dns_support = true

  # Dont share with other accounts
  share_tgw = false

  depends_on = [
    module.eks_ipv6_1.0,
    module.eks_ipv6_2.0,
    module.eks_ipv6_3.0
  ]

  tags = local.tags
}

resource "aws_ec2_transit_gateway_vpc_attachment" "eks_ipv6_1_tgw_attachment" {
  count = var.enable_ipv6_1 ? 1 : 0

  transit_gateway_id = module.tgw.ec2_transit_gateway_id
  subnet_ids         = module.eks_ipv6_1.0.private_subnets
  vpc_id             = module.eks_ipv6_1.0.vpc_id

  dns_support            = "enable"
  ipv6_support           = "enable"
  appliance_mode_support = "disable"

  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  depends_on = [module.eks_ipv6_1.0]

  tags = local.tags
}

resource "aws_ec2_transit_gateway_vpc_attachment" "eks_ipv6_2_tgw_attachment" {
  count = var.enable_ipv6_2 ? 1 : 0

  transit_gateway_id = module.tgw.ec2_transit_gateway_id
  subnet_ids         = module.eks_ipv6_2.0.private_subnets
  vpc_id             = module.eks_ipv6_2.0.vpc_id

  dns_support            = "enable"
  ipv6_support           = "enable"
  appliance_mode_support = "disable"

  depends_on = [module.eks_ipv6_2.0]

  tags = local.tags
}

resource "aws_ec2_transit_gateway_vpc_attachment" "eks_ipv6_3_tgw_attachment" {
  count = var.enable_ipv6_3 ? 1 : 0

  transit_gateway_id = module.tgw.ec2_transit_gateway_id
  subnet_ids         = module.eks_ipv6_3.0.private_subnets
  vpc_id             = module.eks_ipv6_3.0.vpc_id

  dns_support            = "enable"
  ipv6_support           = "enable"
  appliance_mode_support = "disable"

  depends_on = [module.eks_ipv6_3.0]

  tags = local.tags
}

resource "aws_route" "eks_ipv6_1_2_rt" {
  count = (var.enable_ipv6_1 && var.enable_ipv6_2) ? length(module.eks_ipv6_1.0.private_route_table_ids) : 0

  route_table_id              = element(module.eks_ipv6_1.0.private_route_table_ids, count.index)
  destination_ipv6_cidr_block = module.eks_ipv6_2.0.vpc_ipv6_cidr_block
  transit_gateway_id          = module.tgw.ec2_transit_gateway_id
}

resource "aws_route" "eks_ipv6_1_3_rt" {
  count = (var.enable_ipv6_1 && var.enable_ipv6_3) ? length(module.eks_ipv6_1.0.private_route_table_ids) : 0

  route_table_id              = element(module.eks_ipv6_1.0.private_route_table_ids, count.index)
  destination_ipv6_cidr_block = module.eks_ipv6_3.0.vpc_ipv6_cidr_block
  transit_gateway_id          = module.tgw.ec2_transit_gateway_id
}

resource "aws_route" "eks_ipv6_2_1_rt" {
  count = (var.enable_ipv6_2 && var.enable_ipv6_1) ? length(module.eks_ipv6_2.0.private_route_table_ids) : 0

  route_table_id              = element(module.eks_ipv6_2.0.private_route_table_ids, count.index)
  destination_ipv6_cidr_block = module.eks_ipv6_1.0.vpc_ipv6_cidr_block
  transit_gateway_id          = module.tgw.ec2_transit_gateway_id
}

resource "aws_route" "eks_ipv6_2_3_rt" {
  count = (var.enable_ipv6_2 && var.enable_ipv6_3) ? length(module.eks_ipv6_2.0.private_route_table_ids) : 0

  route_table_id              = element(module.eks_ipv6_2.0.private_route_table_ids, count.index)
  destination_ipv6_cidr_block = module.eks_ipv6_3.0.vpc_ipv6_cidr_block
  transit_gateway_id          = module.tgw.ec2_transit_gateway_id
}

resource "aws_route" "eks_ipv6_3_1_rt" {
  count = (var.enable_ipv6_3 && var.enable_ipv6_1) ? length(module.eks_ipv6_3.0.private_route_table_ids) : 0

  route_table_id              = element(module.eks_ipv6_3.0.private_route_table_ids, count.index)
  destination_ipv6_cidr_block = module.eks_ipv6_1.0.vpc_ipv6_cidr_block
  transit_gateway_id          = module.tgw.ec2_transit_gateway_id
}

resource "aws_route" "eks_ipv6_3_2_rt" {
  count = (var.enable_ipv6_3 && var.enable_ipv6_2) ? length(module.eks_ipv6_3.0.private_route_table_ids) : 0

  route_table_id              = element(module.eks_ipv6_3.0.private_route_table_ids, count.index)
  destination_ipv6_cidr_block = module.eks_ipv6_2.0.vpc_ipv6_cidr_block
  transit_gateway_id          = module.tgw.ec2_transit_gateway_id
}
