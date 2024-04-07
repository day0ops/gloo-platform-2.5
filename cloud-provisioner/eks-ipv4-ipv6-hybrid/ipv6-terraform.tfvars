owner = "${CLUSTER_OWNER}"

aws_profile  = "default"
region       = "${EKS_CLUSTER_REGION}"

max_availability_zones_per_cluster = 2
kubernetes_version                 = "1.25"
ec2_ssh_key                        = "eks-ipv6"

# Disable one of the cluster provision
# Replaced by an IPv4 cluster
enable_ipv6_3 = false

enable_dns64 = false