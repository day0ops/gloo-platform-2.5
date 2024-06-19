#!/usr/bin/env bash

###################################################################
# Script Name   : keycloak-auth-code.sh
# Description   : Perform Authorization Code flow with Keycloak
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

set -o pipefail

_UTILITY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
_OUTPUT_TMP_DIR="$_UTILITY_DIR/../._output"
source $_UTILITY_DIR/common.sh

if [[ ! -f "$_OUTPUT_TMP_DIR/keycloak_env.sh" ]]; then
    error_exit "Unable to find keycloak_env.sh to load the Keycloak environment"
fi
source $_OUTPUT_TMP_DIR/keycloak_env.sh

initiate_auth() {
    local username=$1
    local password=$2
    local redirect_url="http://apps.${DOMAIN_NAME}/callback"
    local realm="master"
    local cookie="$_OUTPUT_TMP_DIR/keycloak-cookie.jar"

    local authenticate_url=$(curl -sSL --get --cookie "$cookie" --cookie-jar "$cookie" \
        --data-urlencode "client_id=${CLIENT_ID}" \
        --data-urlencode "redirect_uri=${redirect_url}" \
        --data-urlencode "scope=openid" \
        --data-urlencode "response_type=code" \
        "$KEYCLOAK_URL/realms/$realm/protocol/openid-connect/auth" | htmlq "#kc-form-login" --attribute action)
    authenticate_url=`echo $authenticate_url | sed -e 's/\&amp;/\&/g'`

    local code_url=$(curl -sS --cookie "$cookie" --cookie-jar "$cookie" \
        --data-urlencode "username=$username" \
        --data-urlencode "password=$password" \
        --write-out "%{redirect_url}" \
        "$authenticate_url")

    debug "Following URL with code received from Keycloak : $code_url"
    code=`echo $code_url | awk -F "code=" '{print $2}' | awk '{print $1}'`
    debug "Extracted code : $code"
    debug "Sending code=$code to Keycloak to receive Access token"

    local client_secret=$(echo "$CLIENT_SECRET_BASE64_ENCODED" | base64 -d)
    local access_token=$(curl -sS --cookie "$cookie" --cookie-jar "$cookie" \
        --data-urlencode "client_id=$CLIENT_ID" \
        --data-urlencode "client_secret=$client_secret" \
        --data-urlencode "redirect_uri=$redirect_url" \
        --data-urlencode "code=$code" \
        --data-urlencode "grant_type=authorization_code" \
        "$KEYCLOAK_URL/realms/$realm/protocol/openid-connect/token" \
        | jq -r ".access_token")

    print_info "Successfully generated an access token ====> ${access_token}"

    rm -f $cookie
}