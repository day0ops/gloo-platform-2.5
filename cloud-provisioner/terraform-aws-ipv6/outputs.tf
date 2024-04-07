output "eks_ipv6_1_k8_cluster_name" {
  description = "Cluster ID #1 - Cluster name"
  value       = module.eks_ipv6_1.*.cluster_name
}

output "eks_ipv6_2_k8_cluster_name" {
  description = "Cluster ID #2 - Cluster name"
  value       = module.eks_ipv6_2.*.cluster_name
}

output "eks_ipv6_3_k8_cluster_name" {
  description = "Cluster ID #3 - Cluster name"
  value       = module.eks_ipv6_3.*.cluster_name
}

output "eks_ipv6_1_k8_kubeconfig" {
  description = "Cluster ID #1 - Kubeconfig path"
  value       = module.eks_ipv6_1.*.kubeconfig_path
}

output "eks_ipv6_1_k8_kubeconfig_context" {
  description = "Cluster ID #1 - Kubeconfig context name"
  value       = module.eks_ipv6_1.*.kubeconfig_context
}

output "eks_ipv6_2_k8_kubeconfig" {
  description = "Cluster ID #2 - Kubeconfig path"
  value       = module.eks_ipv6_2.*.kubeconfig_path
}

output "eks_ipv6_2_k8_kubeconfig_context" {
  description = "Cluster ID #2 - Kubeconfig context name"
  value       = module.eks_ipv6_2.*.kubeconfig_context
}

output "eks_ipv6_3_k8_kubeconfig" {
  description = "Cluster ID #3 - Kubeconfig path"
  value       = module.eks_ipv6_3.*.kubeconfig_path
}

output "eks_ipv6_3_k8_kubeconfig_context" {
  description = "Cluster ID #3 - Kubeconfig context name"
  value       = module.eks_ipv6_3.*.kubeconfig_context
}

output "eks_ipv6_1_k8_kubectl" {
  description = "Cluster ID #1 - awsctl command to genereate authentication"
  value       = module.eks_ipv6_1.*.configure_kubectl
}

output "eks_ipv6_2_k8_kubectl" {
  description = "Cluster ID #2 - awsctl command to genereate authentication"
  value       = module.eks_ipv6_2.*.configure_kubectl
}

output "eks_ipv6_3_k8_kubectl" {
  description = "Cluster ID #3 - awsctl command to genereate authentication"
  value       = module.eks_ipv6_3.*.configure_kubectl
}
