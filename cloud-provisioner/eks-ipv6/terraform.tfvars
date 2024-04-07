owner = "${CLUSTER_OWNER}"

aws_profile  = "default"
region       = "${EKS_CLUSTER_REGION}"

max_availability_zones_per_cluster = 2
kubernetes_version                 = "1.25"
ec2_ssh_key                        = "eks-ipv6"