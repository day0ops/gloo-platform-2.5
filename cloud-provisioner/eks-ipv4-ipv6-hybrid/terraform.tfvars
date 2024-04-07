owner = "${CLUSTER_OWNER}"

# -----------------------------------
# EKS
# -----------------------------------
enable_eks             = true
aws_profile            = "default"
eks_region             = "${EKS_CLUSTER_REGION}"
eks_cluster_name       = "gp"
eks_cluster_count      = 1
eks_node_type          = "t3.medium"
eks_nodes              = 3
eks_subnets            = 3
eks_kubernetes_version = "1.25"

# -----------------------------------
# GKE
# -----------------------------------
enable_gke = false

# -----------------------------------
# AKS
# -----------------------------------
enable_aks            = false
aks_service_principal = null
