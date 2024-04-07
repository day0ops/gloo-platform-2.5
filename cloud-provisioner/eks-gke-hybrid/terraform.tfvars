owner = "${CLUSTER_OWNER}"

# -----------------------------------
# EKS
# -----------------------------------
enable_eks             = true
aws_profile            = "default"
eks_region             = "${EKS_CLUSTER_REGION}"
eks_cluster_name       = "gp"
eks_cluster_count      = 2
eks_node_type          = "t3.medium"
eks_nodes              = 3
eks_kubernetes_version = "1.24"

# -----------------------------------
# GKE
# -----------------------------------
enable_gke         = true
gke_project        = "field-engineering-apac"
gke_cluster_count  = 1
gke_region         = "${GKE_CLUSTER_REGION}"
gke_cluster_name   = "gp"
gke_node_pool_size = 3
gke_node_type      = "e2-standard-4"

# -----------------------------------
# AKS
# -----------------------------------
enable_aks            = false
aks_service_principal = null





# -----------------------------------
# EKS
# -----------------------------------
enable_eks             = true
aws_profile            = "default"
eks_region             = "${EKS_CLUSTER_REGION}"
eks_cluster_name       = "gp"
eks_cluster_count      = 2
eks_node_type          = "t3.medium"
eks_nodes              = 3
eks_kubernetes_version = "1.25"

# -----------------------------------
# AKS
# -----------------------------------
enable_aks                      = true
aks_region                      = "${AKS_CLUSTER_REGION}"
aks_cluster_name                = "gp"
aks_cluster_count               = 1
aks_node_type                   = "Standard_D2_v2"
aks_nodes                       = 3
aks_kubernetes_version          = "1.25"
aks_restrict_workstation_access = false
aks_service_principal           = null


# -----------------------------------
# GKE
# -----------------------------------
enable_gke = false