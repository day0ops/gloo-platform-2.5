#!/usr/bin/env bash

###################################################################
# Script Name   : uninstall.sh
# Description   : Clean up tasks for Gloo Platform
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/utility/common.sh

detach_assume_role() {
    local cluster_name=$1
    local policy_name=$2
    local role_name=$3
    local sanitized_policy_name=$(echo "${CLUSTER_OWNER}-${policy_name}" | cut -c -63)
    local sanitized_role_name=$(echo "${cluster_name}-${role_name}" | cut -c -63)

    aws iam detach-role-policy \
        --role-name "${sanitized_role_name}" \
        --policy-arn $(aws iam list-policies --output json | jq --arg pn "${sanitized_policy_name}" -r '.Policies[] | select(.PolicyName == $pn)'.Arn)
    aws iam delete-role \
        --role-name "${sanitized_role_name}"
}

remove_route53_zones() {
    if [[ "$PARENT_DOMAIN_NAME" != "" && "$DOMAIN_NAME" != "" ]]; then
        # Clean up the Route53 records
        export TOP_LEVEL_HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --output json --dns-name "$PARENT_DOMAIN_NAME." | jq -r '.HostedZones[0].Id')
        export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --output json --dns-name "$DOMAIN_NAME." | jq -r '.HostedZones[0].Id')
        aws route53 list-resource-record-sets \
            --hosted-zone-id $HOSTED_ZONE_ID |
            jq -c '.ResourceRecordSets[]' |
            while read -r resourcerecordset; do
                read -r name type <<<$(echo $(jq -r '.Name,.Type' <<<"$resourcerecordset"))
                if [ $type != "NS" -a $type != "SOA" ]; then
                    aws route53 change-resource-record-sets \
                        --hosted-zone-id $HOSTED_ZONE_ID \
                        --change-batch '{"Changes":[
                            {
                                "Action":"DELETE",
                                "ResourceRecordSet":'"$resourcerecordset"'
                            }
                        ]}' \
                        --output text --query 'ChangeInfo.Id'
                fi
            done

        CHANGE_ID=$(aws route53 delete-hosted-zone \
            --id $HOSTED_ZONE_ID \
            --output text --query 'ChangeInfo.Id')
        aws route53 wait resource-record-sets-changed \
            --id "$CHANGE_ID"

        aws route53 list-resource-record-sets \
            --hosted-zone-id $TOP_LEVEL_HOSTED_ZONE_ID |
            jq -c '.ResourceRecordSets[]' |
            while read -r resourcerecordset; do
                read -r name <<<$(echo $(jq -r '.Name' <<<"$resourcerecordset"))
                if [ "$DOMAIN_NAME." = "$name" ]; then
                    CHANGE_ID=$(aws route53 change-resource-record-sets \
                        --hosted-zone-id $TOP_LEVEL_HOSTED_ZONE_ID \
                        --change-batch '{"Changes":[
                            {
                                "Action":"DELETE",
                                "ResourceRecordSet":'"$resourcerecordset"'
                            }
                        ]}' \
                        --output text --query 'ChangeInfo.Id')
                    aws route53 wait resource-record-sets-changed \
                        --id "$CHANGE_ID"
                fi
            done
    fi
}

purge_integration_services() {
    print_info "Purging integration services from all clusters"

    helm --kube-context $MGMT_CONTEXT -n vault del vault
    helm --kube-context $MGMT_CONTEXT -n gitops del argocd
    helm --kube-context $MGMT_CONTEXT -n gitops del gitea

    helm --kube-context $WEST_CONTEXT -n cert-manager del cert-manager
    helm --kube-context $EAST_CONTEXT -n cert-manager del cert-manager
    helm --kube-context $MGMT_CONTEXT -n cert-manager del cert-manager

    helm --kube-context $MGMT_CONTEXT -n external-dns del external-dns
    helm --kube-context $WEST_CONTEXT -n external-dns del external-dns
    helm --kube-context $EAST_CONTEXT -n external-dns del external-dns

    kubectl --context $MGMT_CONTEXT delete ns grafana vault keycloak gitops external-dns cert-manager

    if [[ $WEST_CLOUD_PROVIDER == "eks" || $WEST_CLOUD_PROVIDER == "eks-ipv6" ]]; then
        detach_assume_role "$WEST_CLUSTER" "AWSLoadBalancerControllerIAMPolicy" "aws-load-balancer-controller-role"
        detach_assume_role "$MGMT_CLUSTER" "AWSExternalDNSRoute53Policy" "external-dns-role"
        detach_assume_role "$MGMT_CLUSTER" "AWSCertManagerRoute53IAMPolicy" "cert-manager-role"

        kubectl --context $WEST_CONTEXT delete sa alb-ingress-controller -n kube-system
    fi
    if [[ $EAST_CLOUD_PROVIDER == "eks" || $EAST_CLOUD_PROVIDER == "eks-ipv6" ]]; then
        detach_assume_role "$EAST_CLUSTER" "AWSLoadBalancerControllerIAMPolicy" "aws-load-balancer-controller-role"
        detach_assume_role "$MGMT_CLUSTER" "AWSExternalDNSRoute53Policy" "external-dns-role"
        detach_assume_role "$MGMT_CLUSTER" "AWSCertManagerRoute53IAMPolicy" "cert-manager-role"

        kubectl --context $EAST_CONTEXT delete sa alb-ingress-controller -n kube-system
    fi
    if [[ $MGMT_CLOUD_PROVIDER == "eks" || $MGMT_CLOUD_PROVIDER == "eks-ipv6" ]]; then
        detach_assume_role "$MGMT_CLUSTER" "AWSLoadBalancerControllerIAMPolicy" "aws-load-balancer-controller-role"
        detach_assume_role "$MGMT_CLUSTER" "AWSExternalDNSRoute53Policy" "external-dns-role"
        detach_assume_role "$MGMT_CLUSTER" "AWSCertManagerRoute53IAMPolicy" "cert-manager-role"

        kubectl --context $MGMT_CONTEXT delete sa alb-ingress-controller -n kube-system
    fi
    remove_route53_zones

    helm --kube-context $MGMT_CONTEXT -n kube-system del aws-load-balancer-controller
    helm --kube-context $WEST_CONTEXT -n kube-system del aws-load-balancer-controller
    helm --kube-context $EAST_CONTEXT -n kube-system del aws-load-balancer-controller

    helm --kube-context $WEST_CONTEXT -n kube-system del cilium
    helm --kube-context $EAST_CONTEXT -n kube-system del cilium
}

purge_platform_services() {
    print_info "Purging Gloo Platform services from all clusters"

    kubectl --context $MGMT_CONTEXT scale --replicas=0 deploy/gloo-mesh-mgmt-server -n gloo-mesh
    kubectl --context $MGMT_CONTEXT patch GatewayLifecycleManager istio-ingressgateway -n gloo-mesh -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl --context $MGMT_CONTEXT delete -f $DIR/core/istio/ilm/ingress-gateway.yaml
    kubectl --context $MGMT_CONTEXT patch GatewayLifecycleManager istio-egressgateway -n gloo-mesh -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl --context $MGMT_CONTEXT delete -f $DIR/core/istio/ilm/egress-gateway.yaml
    kubectl --context $MGMT_CONTEXT patch GatewayLifecycleManager istio-eastwestgateway -n gloo-mesh -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl --context $MGMT_CONTEXT delete -f $DIR/core/istio/ilm/eastwest-gateway.yaml
    kubectl --context $MGMT_CONTEXT patch IstioLifecycleManager istiod-control-plane -n gloo-mesh -p '{"metadata":{"finalizers":null}}' --type=merge
    kubectl --context $MGMT_CONTEXT delete -f $DIR/core/istio/ilm/istiod.yaml
    kubectl --context $MGMT_CONTEXT scale --replicas=1 deploy/gloo-mesh-mgmt-server -n gloo-mesh
    # Istio
    sleep 10
    helm --kube-context $WEST_CONTEXT -n istio-system del istio-base
    helm --kube-context $WEST_CONTEXT -n istio-system del istiod
    helm --kube-context $WEST_CONTEXT -n istio-ingress del istio-ingressgateway
    helm --kube-context $WEST_CONTEXT -n istio-eastwest del istio-eastwestgateway
    helm --kube-context $EAST_CONTEXT -n istio-system del istio-base
    helm --kube-context $EAST_CONTEXT -n istio-system del istiod
    helm --kube-context $EAST_CONTEXT -n istio-ingress del istio-ingressgateway
    helm --kube-context $EAST_CONTEXT -n istio-eastwest del istio-eastwestgateway

    # Gloo Platform
    helm --kube-context $WEST_CONTEXT -n gloo-mesh del gloo-platform-agent
    helm --kube-context $EAST_CONTEXT -n gloo-mesh del gloo-platform-agent
    helm --kube-context $WEST_CONTEXT -n gloo-mesh-addons del gloo-platform-agent-addons
    helm --kube-context $EAST_CONTEXT -n gloo-mesh-addons del gloo-platform-agent-addons
    helm --kube-context $WEST_CONTEXT -n gloo-mesh del gloo-platform-crds
    helm --kube-context $EAST_CONTEXT -n gloo-mesh del gloo-platform-crds
    kubectl --context $WEST_CONTEXT delete ns gloo-mesh gloo-mesh-addons
    kubectl --context $EAST_CONTEXT delete ns gloo-mesh gloo-mesh-addons

    helm --kube-context $MGMT_CONTEXT -n gloo-mesh del gloo-platform
    helm --kube-context $MGMT_CONTEXT -n gloo-mesh del gloo-platform-crds
    kubectl --context $MGMT_CONTEXT delete ns gloo-mesh

    kubectl --context $WEST_CONTEXT delete ns istio-eastwest istio-ingress istio-system istio-config
    kubectl --context $EAST_CONTEXT delete ns istio-eastwest istio-ingress istio-system istio-config

    kubectl --context $WEST_CONTEXT delete mutatingwebhookconfiguration $(kubectl --context $WEST_CONTEXT get mutatingwebhookconfiguration -l app=sidecar-injector -o jsonpath='{.items[0].metadata.name}')
    kubectl --context $EAST_CONTEXT delete mutatingwebhookconfiguration $(kubectl --context $EAST_CONTEXT get mutatingwebhookconfiguration -l app=sidecar-injector -o jsonpath='{.items[0].metadata.name}')
    kubectl --context $WEST_CONTEXT delete validatingwebhookconfiguration $(kubectl --context $WEST_CONTEXT get validatingwebhookconfiguration -l app=istiod -o jsonpath='{.items[0].metadata.name}')
    kubectl --context $EAST_CONTEXT delete validatingwebhookconfiguration $(kubectl --context $EAST_CONTEXT get validatingwebhookconfiguration -l app=istiod -o jsonpath='{.items[0].metadata.name}')
}

purge_crds() {
    kubectl --context $1 get crd | grep $2 | awk '{print $1}' | xargs -I {} kubectl --context $1 delete crd {}
}

purge_all_istio_crds() {
    print_info "Purging Gloo Platform and Istio CRDs from all clusters"

    purge_crds $MGMT_CONTEXT istio
    purge_crds $WEST_CONTEXT istio
    purge_crds $EAST_CONTEXT istio
}

help() {
    cat <<EOF
usage: ./`basename $0`

-c | --crds           (Optional)     Clean the crds
-i | --integrations   (Optional)     Clean up all integrations
-h | --help                          Usage
EOF

    exit 1
}

should_purge_crds=false
should_purge_integrations=false

SHORT=c,i,h
LONG=crds,integrations,help
OPTS=$(getopt -q -a -n "uninstall.sh" --options $SHORT --longoptions $LONG -- "$@")
if [[ $? -ne 0 ]]; then
    echo -e "Unrecognized option provided, check help below\n"
    help
fi

eval set -- "$OPTS"

while [ : ]; do
    case "$1" in
    -c | --crds)
        should_purge_crds=true
        shift
        ;;
    -i | --integrations)
        should_purge_integrations=true
        shift
        ;;
    -h | --help)
        help
        ;;
    --)
        shift
        break
        ;;
    esac
done

if ! confirm "Are you sure you want to proceed with uninstalling the Gloo Platform (and relevant integration services) ?"; then
    logger i "Ok, existing then ..."
    exit 0
fi

# First we remove all the Platform related services
purge_platform_services

if [[ "$should_purge_integrations" == true ]]; then
    purge_integration_services
fi

if [[ "$should_purge_crds" == true ]]; then
    purge_all_istio_crds
fi

print_color_info "Uninstall successfully completed 🎉" "fg-green"