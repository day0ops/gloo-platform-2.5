#!/usr/bin/env bash

###################################################################
# Script Name   : common.sh
# Description   : Common utilities
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.2
###################################################################

_UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $_UTILITY_DIR/logging.sh
source $_UTILITY_DIR/logo.sh

log_level info
log_prefix 0

error_exit() {
    logger e "$1"
    exit 1
}

error() {
    logger e "$1"
}

print_info() {
    logger i "$1"
}

print_color_info() {
    logger i:9 "$1" " " "$2"
}

debug() {
    logger d "$1"
}

wait_for_lb_address() {
    local context=$1
    local service=$2
    local ns=$3
    ip=""
    while [ -z $ip ]; do
        echo "Waiting for $service external IP ..."
        ip=$(kubectl --context ${context} -n $ns get service/$service --output=jsonpath='{.status.loadBalancer}' | grep "ingress")
        [ -z "$ip" ] && sleep 5
    done
    logger i "Found $service external IP: ${ip}"
}

validate_env_var() {
    [[ -z ${!1+set} ]] && error_exit "Error: Define ${1} environment variable"

    [[ -z ${!1} ]] && error_exit "${2}"
}

validate_var() {
    [[ -z $1 ]] && error_exit $2
}

has_array_value() {
    local -r item="{$1:?}"
    local -rn items="{$2:?}"

    for value in "${items[@]}"; do
        echo $value
        if [[ "$value" == "$item" ]]; then
            return 0
        fi
    done

    return 1
}

confirm() {
    local prompt default reply

    if [[ ${2:-} = 'Y' ]]; then
        prompt='Y/n'
        default='Y'
    elif [[ ${2:-} = 'N' ]]; then
        prompt='y/N'
        default='N'
    else
        prompt='y/n'
        default=''
    fi

    while true; do
        # Ask the question (not using "read -p" as it uses stderr not stdout)
        logger i "\n$1 [$prompt] "

        # Read the answer (use /dev/tty in case stdin is redirected from somewhere else)
        read -r reply </dev/tty

        # Default?
        if [[ -z $reply ]]; then
            reply=$default
        fi

        # Check if the reply is valid
        case "${reply,,}" in
            y | yes) return 0 ;;
            n | no) return 1 ;;
        esac
    done
}

prompt() {
    while [[ -z $val ]]; do
        read -p "$1"": " val
    done
    echo $val
}

prompt_with_default() {
    read -p "$1"": " val
    if [[ -z $val ]]; then
        val="${2}"
    fi
    echo $val
}

prompt_for_cloud_region() {
    local prompt=$1
    local default_region=$2

    read -p "$prompt"": " selected_region
    if [[ -z $selected_region ]]; then
        selected_region="${default_region}"
    fi

    while true; do
        found_region=$(validate_cloud_region $selected_region)
        if [[ $found_region == "1" ]]; then
            break
        fi
        read -p "Region is invalid, please re-enter: " selected_region
    done

    echo "${selected_region}"
}

validate_cloud_region() {
    local region=$1
    if [[ ! -z $region ]]; then
        local verified_region=$(aws account list-regions --query 'Regions[?RegionName==`'${region}'`]' | jq length)
        if [[ "$verified_region" == 1 ]]; then
            echo "1"
            return 1
        fi
    fi
    echo "0"
}

confirm_purge() {
    if ! confirm "$1"; then
        logger i "Ok, we are giving up on the clean up then, good bye ! ..."
        exit 0
    fi
}

confirm_purge_generic() {
    confirm_purge "Are you sure you want to proceed with the purge of configuration artifacts ❓"
}

cmdline_arg_processor_help() {
    local caller=$1
    cat <<EOF
usage: $caller

-d  | --deploy      Deploy the artifacts
-p  | --purge       Purge the artifacts
-h  | --help        Usage
EOF

    exit 1
}

cmdline_arg_processor() {
    local short=f,i,h
    local long=deploy,purge,help
    local opts=$(getopt -a -n "setup.sh" --options $short --longoptions $long -- "$@")
    if [[ $? -ne 0 ]]; then
        echo -e "Unrecognized option provided, check help below\n"
        help
    fi

    eval set -- "$opts"

    local opt=$1; shift 1
    local source_name=$2; shift 1
    local deploy_func=$2; shift 1
    local purge_func=$2; shift 1

    while :; do
        case "$opt" in
        -d | --deploy)
            $deploy_func
            break
            ;;
        -p | --purge)
            $purge_func
            break
            ;;
        -h | --help)
            cmdline_arg_processor_help $source_name
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unexpected option: $opt"
            cmdline_arg_processor_help $source_name
            ;;
        esac
    done
}