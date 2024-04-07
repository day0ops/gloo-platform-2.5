#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

Provision() {
    echo "------------------------------------------------------------"
    echo "Deploying online boutique on east & west clusters"
    echo "------------------------------------------------------------"
    echo ""

}

Delete() {
    echo "Cleaning up ..."

    kubectl --context ${WEST_CONTEXT} delete ns bookinfo-frontends
    kubectl --context ${WEST_CONTEXT} delete ns bookinfo-backends

    kubectl --context ${EAST_CONTEXT} delete ns bookinfo-frontends
    kubectl --context ${EAST_CONTEXT} delete ns bookinfo-backends
}

shift $((OPTIND-1))
subcommand=$1; shift
case "$subcommand" in
    prov )
        Provision
    ;;
    del )
        Delete
    ;;
    * ) # Invalid subcommand
        if [ ! -z $subcommand ]; then
            echo "Invalid subcommand: $subcommand"
        fi
        exit 1
    ;;
esac