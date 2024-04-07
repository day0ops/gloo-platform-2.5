#!/usr/bin/env bash

###################################################################
# Script Name   : run.sh
# Description   : Provision the given environment topology
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
###################################################################

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR=$DIR/../../._output/env/eks-multicluster

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/../../utility/common.sh

provision() {
    logger i:8 "Provisioning 3 EKS clusters" "#" "fg-yellow"

    mkdir -p $OUT_DIR
    echo "#!/bin/sh" >$OUT_DIR/env.sh
    chmod +x $OUT_DIR/env.sh

    local default_eks_region="ap-northeast-1"

    PROJECT="$(prompt_with_default "Enter the name of the project (Default is 'demo-gloo')" "demo-gloo")"
    CLUSTER_OWNER="$(prompt "Enter the name of the owner (used as a prefix for cloud resources and tagging)")"
    DOMAIN_OWNER="$(prompt_with_default "Enter the name of the domain owner (Default is '$CLUSTER_OWNER')" ${CLUSTER_OWNER})"
    CLUSTER_REGION="$(prompt_for_cloud_region "Enter the AWS region (Default is '${default_eks_region}')" $default_eks_region)"

    EAST_CLOUD_PROVIDER="eks"
    WEST_CLOUD_PROVIDER="eks"
    MGMT_CLOUD_PROVIDER="eks"

    EAST_MESH_NAME="east-mesh"
    WEST_MESH_NAME="west-mesh"
    MGMT_MESH_NAME="mgmt-mesh"

    PARENT_ZONE="apac.fe.gl00.net"
    PARENT_DOMAIN_NAME="${DOMAIN_OWNER}.${PARENT_ZONE}"
    DOMAIN_NAME="${PROJECT}.${PARENT_DOMAIN_NAME}"

    logger i "Confirming entered information:"
    logger i:6 "Project=${PROJECT},Owner=${CLUSTER_OWNER},Region=eks:${CLUSTER_REGION}"
    if ! confirm "Are you sure you want to proceed with provisioning the clusters ?"; then
        logger i "Ok, existing then ..."
        exit 0
    fi

    echo "export PROJECT=\"$PROJECT\"" >>$OUT_DIR/env.sh
    echo "export CLUSTER_OWNER=\"$CLUSTER_OWNER\"" >>$OUT_DIR/env.sh
    echo "export DOMAIN_OWNER=\"$DOMAIN_OWNER\"" >>$OUT_DIR/env.sh

    echo "export EKS_CLUSTER_REGION=\"$CLUSTER_REGION\"" >>$OUT_DIR/env.sh

    echo "export EAST_CLOUD_PROVIDER=\"$EAST_CLOUD_PROVIDER\"" >>$OUT_DIR/env.sh
    echo "export WEST_CLOUD_PROVIDER=\"$WEST_CLOUD_PROVIDER\"" >>$OUT_DIR/env.sh
    echo "export MGMT_CLOUD_PROVIDER=\"$MGMT_CLOUD_PROVIDER\"" >>$OUT_DIR/env.sh

    echo "export EAST_MESH_NAME=\"$EAST_MESH_NAME\"" >>$OUT_DIR/env.sh
    echo "export WEST_MESH_NAME=\"$WEST_MESH_NAME\"" >>$OUT_DIR/env.sh
    echo "export MGMT_MESH_NAME=\"$MGMT_MESH_NAME\"" >>$OUT_DIR/env.sh

    echo "export PARENT_ZONE=\"$PARENT_ZONE\"" >>$OUT_DIR/env.sh
    echo "export PARENT_DOMAIN_NAME=\"$PARENT_DOMAIN_NAME\"" >>$OUT_DIR/env.sh
    echo "export DOMAIN_NAME=\"$DOMAIN_NAME\"" >>$OUT_DIR/env.sh

    mkdir -p $OUT_DIR/tf-template
    rm -rf $OUT_DIR/kubeconfig
    mkdir -p $OUT_DIR/kubeconfig

    source $OUT_DIR/env.sh
    envsubst <$DIR/terraform.tfvars >$OUT_DIR/tf-template/terraform.tfvars

    terraform -chdir=$DIR/../terraform-cloud-provisioner init
    terraform -chdir=$DIR/../terraform-cloud-provisioner apply -var-file $OUT_DIR/tf-template/terraform.tfvars -state $DIR/terraform.tfstate -auto-approve

    sleep 2

    echo "export EAST_CONTEXT=\"$(terraform -chdir=$DIR/../terraform-cloud-provisioner output -state $DIR/terraform.tfstate -json | jq -r '.eks_kubeconfig_context.value[0]')\"" >>$OUT_DIR/env.sh
    echo "export WEST_CONTEXT=\"$(terraform -chdir=$DIR/../terraform-cloud-provisioner output -state $DIR/terraform.tfstate -json | jq -r '.eks_kubeconfig_context.value[1]')\"" >>$OUT_DIR/env.sh
    echo "export MGMT_CONTEXT=\"$(terraform -chdir=$DIR/../terraform-cloud-provisioner output -state $DIR/terraform.tfstate -json | jq -r '.eks_kubeconfig_context.value[2]')\"" >>$OUT_DIR/env.sh

    echo "export EAST_CLUSTER=\"$(terraform -chdir=$DIR/../terraform-cloud-provisioner output -state $DIR/terraform.tfstate -json | jq -r '.eks_cluster_name.value[0]')\"" >>$OUT_DIR/env.sh
    echo "export WEST_CLUSTER=\"$(terraform -chdir=$DIR/../terraform-cloud-provisioner output -state $DIR/terraform.tfstate -json | jq -r '.eks_cluster_name.value[1]')\"" >>$OUT_DIR/env.sh
    echo "export MGMT_CLUSTER=\"$(terraform -chdir=$DIR/../terraform-cloud-provisioner output -state $DIR/terraform.tfstate -json | jq -r '.eks_cluster_name.value[2]')\"" >>$OUT_DIR/env.sh

    KUBECONFIG_FILES=$(terraform -chdir=$DIR/../terraform-cloud-provisioner output -state $DIR/terraform.tfstate -json | jq -r '.eks_kubeconfig.value')
    KUBECONFIG_ENV=""
    for f in $(echo $KUBECONFIG_FILES | tr ":" "\n"); do
        if [[ -f $f ]]; then
            cp $f $OUT_DIR/kubeconfig/
            KUBECONFIG_ENV="$KUBECONFIG_ENV:$OUT_DIR/kubeconfig/$(basename $f)"
        fi
    done
    echo "export KUBECONFIG=\"${KUBECONFIG}${KUBECONFIG_ENV}\"" >>$OUT_DIR/env.sh

    logger i "Source the script manually 'source $OUT_DIR/env.sh'" "fg-green"
}

clean() {
    logger i:8 "Destroying 3 EKS clusters" "#" "fg-yellow"

    if ! confirm "Are you sure you want to proceed with destroying the clusters ?"; then
        logger i "Ok, existing then ..."
        exit 0
    fi

    terraform -chdir=$DIR/../terraform-cloud-provisioner destroy -var-file $OUT_DIR/tf-template/terraform.tfvars -state $DIR/terraform.tfstate -auto-approve
}

shift $((OPTIND - 1))
subcommand=$1
shift
case "$subcommand" in
prov)
    provision
    ;;
clean)
    clean
    ;;
*) # Invalid subcommand
    if [ ! -z $subcommand ]; then
        error_exit "Invalid subcommand: $subcommand"
    fi
    exit 1
    ;;
esac
