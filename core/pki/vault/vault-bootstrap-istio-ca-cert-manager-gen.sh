#!/bin/bash

###################################################################
# Script Name   : vault-bootstrap-istio-ca-cert-manager-gen.sh
# Description   : Manage Istio CA integration with Vault using cert-manager
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CERT_GEN_DIR=$DIR/../../../._output/certs/istio

check_vault_status() {
    vault status &> /dev/null
    while [[ $? -ne 0 ]]; do !!; sleep 5; done
}

generate() {
    echo "------------------------------------------------------------"
    echo "Bootstrapping Istio CA with Vault using cert-manager"
    echo "------------------------------------------------------------"
    echo ""

    # Find the public IP for the vault service
    export VAULT_LB=$(kubectl --context ${MGMT_CONTEXT} get svc -n vault vault \
       -o jsonpath='{.status.loadBalancer.ingress[0].*}')
    export VAULT_ADDR="http://${VAULT_LB}:8200"
    export VAULT_TOKEN="root"

    if [[ -z "${VAULT_LB}" ]]; then
      echo "Unable to obtain the address for the Vault service"
      exit 1
    fi

    check_vault_status

    local cert_gen_dir=$CERT_GEN_DIR
    mkdir -p $CERT_GEN_DIR

    # TODO
}

delete() {
    echo "Cleaning up ..."

    rm -rf $CERT_GEN_DIR
}

shift $((OPTIND-1))
subcommand=$1; shift
case "$subcommand" in
    gen )
        generate
    ;;
    del )
        delete
    ;;
    * ) # Invalid subcommand
        if [ ! -z $subcommand ]; then
            echo "Invalid subcommand: $subcommand"
        fi
        exit 1
    ;;
esac