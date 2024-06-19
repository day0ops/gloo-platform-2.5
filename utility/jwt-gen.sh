#!/usr/bin/env bash

###################################################################
# Script Name   : jwt-gen.sh
# Description   : JWT Generator utilities
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

set -o pipefail

_UTILITY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source $_UTILITY_DIR/common.sh

b64enc() { openssl enc -base64 -A | tr '+/' '-_' | tr -d '='; }
json() { jq -c . | LC_CTYPE=C tr -d '\n'; }
hs_sign() { openssl dgst -binary -sha"${1}" -hmac "${2}"; }
rs_sign() { openssl dgst -binary -sha"${1}" -sign <(printf '%s\n' "${2}"); }
decode() { jq -R 'split(".") | .[1] | @base64d | fromjson' <<< "${1}"; }

gen_rsa256_token() {
    local gen_dir=$1;shift
    local force_create_dir=${1:-true};shift
    local force_gen_key=${1:-true};shift

    if [[ "$force_create_dir" == true ]]; then
        echo "Ohhhh nooo"
        rm -rf $gen_dir
    fi

    mkdir -p $gen_dir

    if [[ (! -f "$gen_dir/private.key") || ("$force_gen_key" == true) ]]; then
        echo "Ohhhh nooo"
        openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
            -subj "/C=US/ST=MA/L=Boston/O=Solo.io/OU=DevOps/CN=localhost" \
            -keyout $gen_dir/private.key \
            -out $gen_dir/public_cert.pem 2>/dev/null
        openssl x509 -pubkey -noout -in $gen_dir/public_cert.pem > $gen_dir/public_key.pem 2>/dev/null
    fi 

    rsa_token=$(cat $gen_dir/private.key)

    gen_jwt_token rs256 "$rsa_token" "$@"
}

gen_jwt_token() {
    print_info "Generating a valid JWT token ...."

    local algo=$1
    local jwt_secret=$2
    local payload=$3
    local encode_secret=$4
    local expiration_in_sec=$5

    [ -n "$algo" ] || error_exit "Algorithm not specified, RS256 or HS256."
    [ -n "$jwt_secret" ] || error_exit "Secret not provided."

    algo=${algo^^}

    local default_payload='{
    }'

    # Number of seconds to expire token, default 1h
    local expire_seconds="${expiration_in_sec:-3600}"

    # Check if secret should be base64 encoded
    ${encode_secret:-false} && jwt_secret=$(printf %s "$jwt_secret" | base64 --decode)

    header_template='{
        "typ": "JWT",
        "kid": "0001"
    }'

    gen_header=$(jq -c \
        --arg alg "${algo}" \
        '
        .alg = $alg
        ' <<<"${header_template}" | tr -d '\n') || error_exit "Unable to generate JWT header"

    # Generate payload
    gen_payload=$(jq -c \
        --arg iat_str "$(date +%s)" \
        --arg alg "${algo}" \
        --arg expiry_str "${expiration_in_sec:-7200}" \
        '
        ($iat_str | tonumber) as $iat
        | ($expiry_str | tonumber) as $expiry
        | .alg = $alg
        | .iat = $iat
        | .exp = ($iat + $expiry)
        | .nbf = $iat
        ' <<<"${payload:-$default_payload}" | tr -d '\n') || error_exit "Unable to generate JWT payload"

    signed_content="$(json <<<"$gen_header" | b64enc).$(json <<<"$gen_payload" | b64enc)"

    # Based on algo sign the content
    case ${algo} in
        HS*) signature=$(printf %s "$signed_content" | hs_sign "${algo#HS}" "$jwt_secret" | b64enc) ;;
        RS*) signature=$(printf %s "$signed_content" | rs_sign "${algo#RS}" "$jwt_secret" | b64enc) ;;
        *) echo "Unknown algorithm" >&2; return 1 ;;
    esac

    print_info "Successfully generated a JWT token. ** Expires in ${expire_seconds} seconds ** ====> ${signed_content}.${signature}"
}