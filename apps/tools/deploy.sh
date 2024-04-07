#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/../../utility/common.sh

provision() {
    logger i:8 "Deploying tools on all worker clusters" "=" "fg-yellow"

    kubectl --context ${WEST_CONTEXT} create ns tools
    kubectl --context ${WEST_CONTEXT} label namespace tools istio.io/rev=$REVISION --overwrite

    kubectl --context ${WEST_CONTEXT} create ns non-mesh-tools

    kubectl --context ${WEST_CONTEXT} -n tools apply -f $DIR/httpbin.yaml
    kubectl --context ${WEST_CONTEXT} -n tools apply -f $DIR/httpbin-v2.yaml
    kubectl --context ${WEST_CONTEXT} -n tools apply -f $DIR/httpbin-headless.yaml
    kubectl --context ${WEST_CONTEXT} -n tools apply -f $DIR/sleep.yaml
    kubectl --context ${WEST_CONTEXT} -n tools apply -f $DIR/swissarmy.yaml

    kubectl --context ${WEST_CONTEXT} -n non-mesh-tools apply -f $DIR/non-mesh-httpbin.yaml
    kubectl --context ${WEST_CONTEXT} -n non-mesh-tools apply -f $DIR/non-mesh-sleep.yaml

    kubectl --context ${EAST_CONTEXT} create ns tools
    kubectl --context ${EAST_CONTEXT} label namespace tools istio.io/rev=$REVISION --overwrite

    kubectl --context ${EAST_CONTEXT} create ns non-mesh-tools

    kubectl --context ${EAST_CONTEXT} -n tools apply -f $DIR/httpbin.yaml
    kubectl --context ${EAST_CONTEXT} -n tools apply -f $DIR/httpbin-v2.yaml
    kubectl --context ${EAST_CONTEXT} -n tools apply -f $DIR/sleep.yaml
    kubectl --context ${EAST_CONTEXT} -n tools apply -f $DIR/swissarmy.yaml

    kubectl --context ${EAST_CONTEXT} -n non-mesh-tools apply -f $DIR/non-mesh-httpbin.yaml
    kubectl --context ${EAST_CONTEXT} -n non-mesh-tools apply -f $DIR/non-mesh-sleep.yaml
}

delete() {
    if ! confirm "Are you sure you want to proceed with the cleanup ?"; then
        logger i "Ok, existing then ..."
        exit 0
    fi

    kubectl --context ${WEST_CONTEXT} delete ns tools non-mesh-tools
    kubectl --context ${EAST_CONTEXT} delete ns tools non-mesh-tools
}

shift $((OPTIND-1))
subcommand=$1; shift
case "$subcommand" in
    prov )
        provision
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