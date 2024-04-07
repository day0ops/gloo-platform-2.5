#!/usr/bin/env bash

###################################################################
# Script Name   : provision-integrations.sh
# Description   : Provision required integrations
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/../utility/common.sh

create_iam_oidc_identity_provider() {
    local cluster_name=$1
    local issuer_url=$2
    validate_env_var cluster_name "Cluster name is not set"
    validate_env_var issuer_url "Issuer URL is not set"

    # Ask OIDC Provider for JWKS host (remove schema and path with sed)
    local jwks_uri=$(curl -s ${issuer_url}/.well-known/openid-configuration | jq -r '.jwks_uri' | sed -e "s/^https:\/\///" | sed 's/\/.*//')

    # Extract all certificates in separate files
    temp=$DIR/../._output/eks-oidc
    mkdir -p $temp

    openssl s_client -servername $jwks_uri -showcerts -connect $jwks_uri:443 < /dev/null 2>/dev/null | \
        awk -v dir="$temp" '/-----BEGIN CERTIFICATE-----/,/-----END CERTIFICATE-----/{ if(/BEGIN/){a++}; out=dir"/cert00"a".crt"; print >out }'

    # Assume last found certificate in chain is the root_ca
    local root_ca=$(ls -1 $temp/* | tail -1)

    # Extract fingerprint in desired format (no header, no colons)
    local thumbprint=$(openssl x509 -fingerprint -noout -in $root_ca | sed 's/^.*=//' | sed 's/://g')

    rm -rf $temp

    aws iam create-open-id-connect-provider \
        --url $issuer_url \
        --thumbprint-list $thumbprint \
        --client-id-list sts.amazonaws.com
}

create_aws_identity_role_and_attach_predefined_policy_for_ebs_csi_driver() {
    local context=$1
    local cluster_name=$2
    local cluster_region=$3
    local policy_name=$4
    local role_name=$5
    local sa_name=$6
    local sa_namespace=$7
    validate_env_var context "Context is not set"
    validate_env_var cluster_name "Cluster name is not set"
    validate_env_var cluster_region "Cluster region is not set"
    validate_env_var policy_name "Policy name is not set"
    validate_env_var role_name "Role name is not set"
    validate_env_var sa_name "Service account name is not set"
    validate_env_var sa_namespace "Namespace for service account is not set"

    local sanitized_role_name=`echo "${cluster_name}-${role_name}" | cut -c -63`

    local issuer_url=$(aws eks describe-cluster \
                    --name $cluster_name \
                    --region $cluster_region \
                    --query cluster.identity.oidc.issuer \
                    --output text)
    [[ -z $issuer_url ]] && error_exit "OIDC provider url not found, unable to proceed with the identity creation"

    create_iam_oidc_identity_provider $cluster_name $issuer_url

    local issuer_hostpath=$(echo $issuer_url | cut -f 3- -d'/')
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local provider_arn="arn:aws:iam::${account_id}:oidc-provider/${issuer_hostpath}"
    cat > $DIR/../._output/irp-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${issuer_hostpath}:sub": "system:serviceaccount:${sa_namespace}:${sa_name}"
        }
      }
    }
  ]
}
EOF

    aws iam create-role \
        --role-name "${sanitized_role_name}" \
        --assume-role-policy-document file://$DIR/../._output/irp-trust-policy.json

    aws iam attach-role-policy \
        --policy-arn "arn:aws:iam::aws:policy/service-role/${policy_name}" \
        --role-name "${sanitized_role_name}"

    local role_arn=$(aws iam get-role \
        --role-name "${sanitized_role_name}" \
        --query Role.Arn --output text)

    aws eks create-addon --cluster-name $cluster_name \
        --addon-name aws-ebs-csi-driver \
        --service-account-role-arn "${role_arn}" \
        --region $cluster_region
}

create_aws_identity_provider_with_policy_and_service_account() {
    local context=$1
    local cluster_name=$2
    local cluster_region=$3
    local policy_name=$4
    local policy_file=$5
    local role_name=$6
    local sa_name=$7
    local sa_namespace=$8
    validate_env_var context "Context is not set"
    validate_env_var cluster_name "Cluster name is not set"
    validate_env_var cluster_region "Cluster region is not set"
    validate_env_var policy_name "Policy name is not set"
    validate_env_var role_name "Role name is not set"
    validate_env_var sa_name "Service account name is not set"
    validate_env_var sa_namespace "Namespace for service account is not set"

    local sanitized_policy_name=`echo "${CLUSTER_OWNER}-${policy_name}" | cut -c -63`
    local sanitized_role_name=`echo "${cluster_name}-${role_name}" | cut -c -63`

    local issuer_url=$(aws eks describe-cluster \
                    --name $cluster_name \
                    --region $cluster_region \
                    --query cluster.identity.oidc.issuer \
                    --output text)
    [[ -z $issuer_url ]] && error_exit "OIDC provider url not found, unable to proceed with the identity creation"

    create_iam_oidc_identity_provider $cluster_name $issuer_url

    aws iam create-policy \
        --policy-name "${sanitized_policy_name}" \
        --policy-document file://$DIR/$policy_file

    local issuer_hostpath=$(echo $issuer_url | cut -f 3- -d'/')
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local provider_arn="arn:aws:iam::${account_id}:oidc-provider/${issuer_hostpath}"
    cat > $DIR/../._output/irp-trust-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${provider_arn}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${issuer_hostpath}:sub": "system:serviceaccount:${sa_namespace}:${sa_name}"
        }
      }
    }
  ]
}
EOF

    aws iam create-role \
        --role-name "${sanitized_role_name}" \
        --assume-role-policy-document file://$DIR/../._output/irp-trust-policy.json
    aws iam update-assume-role-policy \
        --role-name "${sanitized_role_name}" \
        --policy-document file://$DIR/../._output/irp-trust-policy.json
    aws iam attach-role-policy \
        --role-name "${sanitized_role_name}" \
        --policy-arn $(aws iam list-policies --output json | jq --arg pn "${sanitized_policy_name}" -r '.Policies[] | select(.PolicyName == $pn)'.Arn)
    local role_arn=$(aws iam get-role \
        --role-name "${sanitized_role_name}" \
        --query Role.Arn --output text)

    [[ -z $role_arn ]] && error_exit "Role arn is not computed, unable to proceed with the identity creation"

    kubectl --context $context \
        create ns $sa_namespace
    kubectl --context $context \
        create sa $sa_name -n $sa_namespace
    kubectl --context $context \
        annotate sa $sa_name -n $sa_namespace "eks.amazonaws.com/role-arn=${role_arn}"
}

install_alb_controller() {
    local context=$1
    local cluster_name=$2
    local cloud_provider=$3
    local cluster_region=$4
    local sa_namespace="kube-system"

    print_info "Installing ALB Controller on ${context} context"

    validate_env_var context "Kubernetes context not set"
    validate_env_var cluster_name "Cluster name not set"
    validate_env_var cloud_provider "Cluster provider not set"
    validate_env_var cluster_region "Cluster region not set"

    if [[ "$cloud_provider" == "eks" ]]; then
        # Create an IAM OIDC identity provider and policy
        create_aws_identity_provider_with_policy_and_service_account $context \
            $cluster_name \
            $cluster_region \
            "AWSLoadBalancerControllerIAMPolicy" \
            "alb-controller/iam-policy.json" \
            "alb-ingress-controller-role" \
            "alb-ingress-controller" \
            $sa_namespace
        # Get the VPC ID
        export VPC_ID=$(aws ec2 describe-vpcs --region $cluster_region \
            --filters Name=tag:cluster,Values=${cluster_name} | jq -r '.Vpcs[]|.VpcId')
    elif [[ "$cloud_provider" == "eks-ipv6" ]]; then
        export ALB_ARN=$(aws iam get-role --role-name "$cluster_name-alb" --query 'Role.[Arn]' --output text)
        export VPC_ID=$(aws ec2 describe-vpcs --region $cluster_region \
            --filters Name=tag:Name,Values=${cluster_name} | jq -r '.Vpcs[]|.VpcId')
        envsubst < <(cat $DIR/alb-controller/cluster-role-binding.yaml) | kubectl --context $context apply -n $sa_namespace -f -
    else
        error "ALB controller not supported on $cloud_provider"
        return
    fi

    # Install ALB controller
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update eks

    export CLUSTER_NAME=$cluster_name
    envsubst < <(cat $DIR/alb-controller/helm-values.yaml) | helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        --kube-context ${context} \
        -n ${sa_namespace} -f -

    kubectl --context ${context} \
        -n kube-system wait deploy/aws-load-balancer-controller --for condition=Available=True --timeout=90s
}

install_external_dns() {
    local context=$1
    local cluster_name=$2
    local cloud_provider=$3
    local cluster_region=$4
    local sa_namespace="external-dns"

    print_info "Installing External DNS on ${context} cluster"

    validate_env_var context "Kubernetes context not set"
    validate_env_var cluster_name "Cluster name not set"
    validate_env_var cloud_provider "Cluster provider not set"
    validate_env_var PARENT_DOMAIN_NAME "Parent domain name is not set"
    validate_env_var DOMAIN_NAME "Domain name is not set"

    if [[ "$cloud_provider" == "eks" || "$cloud_provider" == "eks-ipv6" ]]; then
        validate_env_var cluster_region "Cluster region not set"

        # Create an IAM OIDC identity provider and policy
        create_aws_identity_provider_with_policy_and_service_account $context \
            $cluster_name \
            $cluster_region \
            "AWSExternalDNSRoute53Policy" \
            "external-dns/iam-policy.json" \
            "external-dns-role" \
            "external-dns" \
            $sa_namespace

        # Create the parent zone if it doesnt exist
        if [[ $(aws route53 list-hosted-zones-by-name | jq --arg name "$PARENT_DOMAIN_NAME." -r '.HostedZones | .[] | select(.Name=="\($name)") | .Id') == "" ]]; then
            # Create the hosted zone
            aws route53 create-hosted-zone --name "$PARENT_DOMAIN_NAME." --caller-reference "${cluster_name}-$(date +%s)"

            local top_level_hosted_zone_id=$(aws route53 list-hosted-zones-by-name --output json --dns-name "$PARENT_ZONE." | jq -r '.HostedZones[0].Id')
            export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --output json --dns-name "$PARENT_DOMAIN_NAME." | jq -r '.HostedZones[0].Id')
            local ns_list=$(aws route53 list-resource-record-sets --output json --hosted-zone-id "$HOSTED_ZONE_ID" \
                | jq -r '.ResourceRecordSets' | jq -r 'map(select(.Type == "NS"))' | jq -r '.[0].ResourceRecords')

            aws route53 change-resource-record-sets \
                --hosted-zone-id "$top_level_hosted_zone_id" \
                --change-batch file://<(cat << EOF
{
    "Comment": "$PARENT_DOMAIN_NAME nameservers",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$PARENT_DOMAIN_NAME",
                "Type": "NS",
                "TTL": 300,
                "ResourceRecords": $ns_list
            }
        }
    ]
}
EOF
            )
        fi

        # If the hosted zone doesnt exist then create it
        if [[ $(aws route53 list-hosted-zones-by-name | jq --arg name "$DOMAIN_NAME." -r '.HostedZones | .[] | select(.Name=="\($name)") | .Id') == "" ]]; then
            # Create the hosted zone
            aws route53 create-hosted-zone --name "$DOMAIN_NAME." --caller-reference "${cluster_name}-$(date +%s)"

            # Add the nameservers to the top level zone
            local top_level_hosted_zone_id=$(aws route53 list-hosted-zones-by-name --output json --dns-name "$PARENT_DOMAIN_NAME." | jq -r '.HostedZones[0].Id')
            export HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --output json --dns-name "$DOMAIN_NAME." | jq -r '.HostedZones[0].Id')
            local ns_list=$(aws route53 list-resource-record-sets --output json --hosted-zone-id "$HOSTED_ZONE_ID" \
                | jq -r '.ResourceRecordSets' | jq -r 'map(select(.Type == "NS"))' | jq -r '.[0].ResourceRecords')

            aws route53 change-resource-record-sets \
                --hosted-zone-id "$top_level_hosted_zone_id" \
                --change-batch file://<(cat << EOF
{
    "Comment": "$DOMAIN_NAME nameservers",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$DOMAIN_NAME",
                "Type": "NS",
                "TTL": 120,
                "ResourceRecords": $ns_list
            }
        }
    ]
}
EOF
            )
        else
            echo "Hosted zone '$DOMAIN_NAME.' already exists !"
        fi
    elif [[ "$cloud_provider" == "gke" ]]; then
        export MANAGED_ZONE_NAME=$(echo ${DOMAIN_NAME} | sed 's/\./-/g')
        if ! gcloud dns record-sets list --zone "$MANAGED_ZONE_NAME" --name "${DOMAIN_NAME}." > /dev/null 2>&1; then
            gcloud dns managed-zones create "$MANAGED_ZONE_NAME" --dns-name "${DOMAIN_NAME}." \
                --description "Automatically managed zone by kubernetes.io/external-dns"
            local ns_list=$(gcloud dns record-sets list \
                --zone "$MANAGED_ZONE_NAME" --name "${DOMAIN_NAME}." --type NS --format json | jq -r '.[].rrdatas | to_entries | map( {Value: .value} )')

            # Add record and NS's to top level domain
            local top_level_hosted_zone_id=$(aws route53 list-hosted-zones-by-name --output json --dns-name "$PARENT_DOMAIN_NAME." | jq -r '.HostedZones[0].Id')
            aws route53 change-resource-record-sets \
                --hosted-zone-id "$top_level_hosted_zone_id" \
                --change-batch file://<(cat << EOF
{
    "Comment": "$DOMAIN_NAME nameservers",
    "Changes": [
        {
            "Action": "UPSERT",
            "ResourceRecordSet": {
                "Name": "$DOMAIN_NAME",
                "Type": "NS",
                "TTL": 120,
                "ResourceRecords": $ns_list
            }
        }
    ]
}
EOF
        )
        fi
    else
        error "External DNS is not supported on $cloud_provider"
        return
    fi

    # Deploy External DNS
    helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
    helm repo update external-dns

    if [[ "$cloud_provider" == "eks" || "$cloud_provider" == "eks-ipv6" ]]; then
        envsubst < <(cat $DIR/external-dns/eks-helm-values.yaml) | helm install external-dns external-dns/external-dns \
            --kube-context ${context} \
            --create-namespace \
            -n external-dns -f -
    elif [[ "$cloud_provider" == "gke" ]]; then
        envsubst < <(cat $DIR/external-dns/gke-helm-values.yaml) | helm install external-dns external-dns/external-dns \
            --kube-context ${context} \
            --create-namespace \
            -n external-dns -f -
    fi

    kubectl --context ${context} \
        -n external-dns wait deploy/external-dns --for condition=Available=True --timeout=90s
}

install_cert_manager() {
    local context=$1
    local cluster_name=$2
    local cloud_provider=$3
    local include_pca=$4
    local cluster_region=$5
    local sa_namespace="cert-manager"

    print_info "Installing Cert Manager on ${context} cluster"

    validate_env_var context "Kubernetes context not set"
    validate_env_var cluster_name "Cluster name not set"
    validate_env_var cloud_provider "Cluster provider not set"
    validate_env_var CERT_MANAGER_VERSION "Cert manager version is not set with \$CERT_MANAGER_VERSION"

    if [[ "$cloud_provider" == "eks" || "$cloud_provider" == "eks-ipv6" ]]; then
        validate_env_var cluster_region "Cluster region not set"

        # Create an IAM OIDC identity provider and policy
        create_aws_identity_provider_with_policy_and_service_account $context \
            $cluster_name \
            $cluster_region \
            "AWSCertManagerRoute53IAMPolicy" \
            "cert-manager/iam-policy.json" \
            "cert-manager-role" \
            "cert-manager" \
            $sa_namespace
    elif [[ "$cloud_provider" == "gke" ]]; then
        export GKE_PROJECT_ID=$(gcloud config get-value project)
        gcloud iam service-accounts create cert-manager-dns01-solver \
            --display-name "cert-manager-dns01-solver"
        gcloud projects add-iam-policy-binding $GKE_PROJECT_ID \
            --member serviceAccount:cert-manager-dns01-solver@$GKE_PROJECT_ID.iam.gserviceaccount.com \
            --role roles/dns.admin
        gcloud iam service-accounts keys create $DIR/../._output/dns01-solver_key.json \
            --iam-account cert-manager-dns01-solver@$GKE_PROJECT_ID.iam.gserviceaccount.com
        kubectl --context ${context} -n cert-manager create secret generic clouddns-dns01-solver-svc-acct \
            --from-file=key.json=$DIR/../._output/dns01-solver_key.json
    fi

    # Deploy Cert manager
    helm repo add jetstack https://charts.jetstack.io
    helm repo update jetstack

    kubectl --context ${context} \
        apply -f https://github.com/cert-manager/cert-manager/releases/download/$CERT_MANAGER_VERSION/cert-manager.crds.yaml

    if [[ "$cloud_provider" == "eks" || "$cloud_provider" == "eks-ipv6" ]]; then
        helm install cert-manager jetstack/cert-manager -n cert-manager \
            --kube-context ${context} \
            --create-namespace \
            --version ${CERT_MANAGER_VERSION} \
            -f $DIR/cert-manager/eks-helm-values.yaml
    else
        helm install cert-manager jetstack/cert-manager -n cert-manager \
            --kube-context ${context} \
            --create-namespace \
            --version ${CERT_MANAGER_VERSION} \
            -f $DIR/cert-manager/helm-values.yaml
    fi

    kubectl --context ${context} \
        -n cert-manager wait deploy/cert-manager --for condition=Available=True --timeout=90s
    kubectl --context ${context} \
        -n cert-manager wait deploy/cert-manager-cainjector --for condition=Available=True --timeout=90s
    kubectl --context ${context} \
        -n cert-manager wait deploy/cert-manager-webhook --for condition=Available=True --timeout=90s

    # Cluster wide issuer
    if [[ "$cloud_provider" == "eks" || "$cloud_provider" == "eks-ipv6" ]]; then
        export CLUSTER_REGION=$EKS_CLUSTER_REGION
        envsubst < <(cat $DIR/cert-manager/certificate-issuer-eks.yaml) | kubectl --context ${context} apply -f -
        if [[ "$include_pca" == true ]]; then
            helm repo add aws-pca https://cert-manager.github.io/aws-privateca-issuer
            helm repo update aws-pca
            helm upgrade --install aws-pca-issuer aws-pca/aws-privateca-issuer \
                --kube-context ${context} \
                --namespace cert-manager \
                --set serviceAccount.create=false \
                --set serviceAccount.name="aws-pca-issuer"

            kubectl --context ${context} \
                -n cert-manager wait deploy/aws-pca-issuer-aws-privateca-issuer --for condition=Available=True --timeout=90s
        fi
    elif [[ "$cloud_provider" == "gke" ]]; then
        envsubst < <(cat $DIR/cert-manager/certificate-issuer-gke.yaml) | kubectl --context ${context} apply -f -
    fi
}

install_vault() {
    print_info "Installing Vault on management cluster"

    local context=$1

    validate_env_var context "Kubernetes context is not set"
    validate_env_var VAULT_VERSION "Vault version is not specified as \$VAULT_VERSION environment variable"

    # Deploy Vault
    helm repo add hashicorp https://helm.releases.hashicorp.com
    helm repo update hashicorp

    helm install vault hashicorp/vault -n vault \
        --kube-context ${context} \
        --version ${VAULT_VERSION} \
        --create-namespace \
        -f $DIR/vault/helm-values.yaml

    # Wait for vault to be ready
    kubectl --context ${context} wait --for=condition=ready pod vault-0 -n vault

    wait_for_lb_address $context "vault" "vault"

    export VAULT_LB=$(kubectl --context ${context} get svc -n vault vault \
        -o jsonpath='{.status.loadBalancer.ingress[0].*}') 
    validate_env_var VAULT_LB "Unable to get the load balancer address for Vault"
    
    echo export VAULT_LB=$(kubectl --context ${context} get svc -n vault vault \
        -o jsonpath='{.status.loadBalancer.ingress[0].*}') > $DIR/../._output/vault_env.sh
    echo export VAULT_ADDR="http://${VAULT_LB}:8200" >> $DIR/../._output/vault_env.sh
}

install_grafana() {
    print_info "Installing Grafana on management cluster"

    local context=$1
    local localport=3000

    validate_env_var context "Kubernetes context is not set"
    validate_env_var ISTIO_VERSION "Istio version is not set"

    # Install grafana
    kubectl --context ${context} create ns grafana
    kubectl --context ${context} apply -f $DIR/grafana/grafana-deployment.yaml \
        -n grafana

    kubectl --context ${context} \
        -n grafana wait deploy/grafana --for condition=Available=True --timeout=90s

    # Portforward to service
    kubectl --context ${context} -n grafana port-forward svc/grafana $localport:3000 > /dev/null 2>&1 &
    pid=$!

    # Kill the port-forward regardless of how this script exits
    trap '{
        # echo killing $pid
        kill $pid
    }' EXIT

    # Wait for $localport to become available
    while ! nc -vz localhost $localport > /dev/null 2>&1 ; do
        # echo sleeping
        sleep 0.1
    done

    # Address of Grafana
    local grafana_host="http://localhost:3000"
    # The name of the Prometheus data source to use
    local grafana_datasource="Prometheus"

    # Import all Istio dashboards
    for dashboard in 7639 11829 7636 7630 7645; do
        revision="$(curl -s https://grafana.com/api/dashboards/${dashboard}/revisions -s | jq ".items[] | select(.description | contains(\"${ISTIO_VERSION}\")) | .revision")"
        curl -s https://grafana.com/api/dashboards/$dashboard/revisions/$revision/download > /tmp/dashboard.json
        echo "Importing $(cat /tmp/dashboard.json | jq -r '.title') (revision ${revision}, id ${dashboard})..."
        curl -s -k -XPOST \
            -H "Accept: application/json" \
            -H "Content-Type: application/json" \
            -d "{\"dashboard\":$(cat /tmp/dashboard.json),\"overwrite\":true, \
                \"inputs\":[{\"name\":\"DS_PROMETHEUS\",\"type\":\"datasource\", \
                \"pluginId\":\"prometheus\",\"value\":\"$grafana_datasource\"}]}" \
            $grafana_host/api/dashboards/import
        echo -e "\nDone\n"
    done
}

install_keycloak() {
    local context=$1
    local cluster_name=$2
    local cloud_provider=$3
    local cluster_region=$4

    print_info "Installing Keycloak on ${context} cluster"

    validate_env_var context "Kubernetes context is not set"
    validate_env_var cluster_name "Cluster name not set"
    validate_env_var cloud_provider "Cloud provider not set"
    validate_env_var cluster_region "Cluster region not set"
    validate_env_var KEYCLOAK_VERSION "Keycloak version is not specified as \$KEYCLOAK_VERSION environment variable"

    install_ebs_csi_driver $context $cluster_name $cloud_provider $cluster_region

    envsubst < <(cat $DIR/keycloak/helm-values.yaml) | helm install keycloak oci://registry-1.docker.io/bitnamicharts/keycloak -n keycloak \
        --kube-context ${context} \
        --version ${KEYCLOAK_VERSION} \
        --create-namespace \
        -f -

    envsubst < <(cat $DIR/keycloak/tls.yaml) | kubectl --context ${context} apply -f -

    kubectl --context ${context} \
        -n keycloak rollout status --watch statefulset/keycloak --timeout=120s

    wait_for_lb_address $context "keycloak" "keycloak"

    sleep 120

    export ENDPOINT_KEYCLOAK="keycloak.${DOMAIN_NAME}"
    export KEYCLOAK_URL=https://${ENDPOINT_KEYCLOAK}

    # Wait for DNS to resolve
    until [ ! -z "$(dig +short $ENDPOINT_KEYCLOAK)" ]; do true; done

    echo export KEYCLOAK_URL=$KEYCLOAK_URL > $DIR/../._output/keycloak_env.sh

    export KEYCLOAK_TOKEN=$(curl -d "client_id=admin-cli" -d "username=admin" -d "password=passwd00" -d "grant_type=password" "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" | jq -r .access_token)
    echo export KEYCLOAK_TOKEN=$KEYCLOAK_TOKEN >> $DIR/../._output/keycloak_env.sh

    # Create initial token to register the client
    read -r client token <<<$(curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" -d '{"expiration": 0, "count": 1}' $KEYCLOAK_URL/admin/realms/master/clients-initial-access | jq -r '[.id, .token] | @tsv')
    export CLIENT_ID=${client}
    echo export CLIENT_ID=$CLIENT_ID >> $DIR/../._output/keycloak_env.sh

    # Register the client
    read -r id secret <<<$(curl -X POST -d "{ \"clientId\": \"${CLIENT_ID}\" }" -H "Content-Type:application/json" -H "Authorization: bearer ${token}" ${KEYCLOAK_URL}/realms/master/clients-registrations/default| jq -r '[.id, .secret] | @tsv')
    export CLIENT_SECRET=${secret}
    echo export CLIENT_SECRET_BASE64_ENCODED=$(echo -n ${CLIENT_SECRET} | base64) >> $DIR/../._output/keycloak_env.sh

    # Add allowed redirect URIs
    curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X PUT -H "Content-Type: application/json" \
        -d '{"serviceAccountsEnabled": true, "directAccessGrantsEnabled": true, "authorizationServicesEnabled": true, "redirectUris": ["http://localhost:8090/oidc-callback", "'http://apps.${DOMAIN_NAME}'/callback", "'https://apps.${DOMAIN_NAME}'/callback", "'http://gloo-mesh-ui.${DOMAIN_NAME}'/callback", "'http://api.${DOMAIN_NAME}'/callback", "'https://api.${DOMAIN_NAME}'/callback"]}' \
        $KEYCLOAK_URL/admin/realms/master/clients/${id}

    # Add the group attribute in the JWT token returned by Keycloak
    curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" \
        -d '{"name": "Groups Mapper", "protocol": "openid-connect", "protocolMapper": "oidc-group-membership-mapper", "config": {"claim.name": "groups", "jsonType.label": "String", "id.token.claim": "true", "access.token.claim": "true", "userinfo.token.claim": "true"}}' \
        $KEYCLOAK_URL/admin/realms/master/clients/${id}/protocol-mappers/models

    # New groups
    curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" \
        -d '{"name": "dev-team"}' \
        $KEYCLOAK_URL/admin/realms/master/groups
    curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" \
        -d '{"name": "ops-team"}' \
        $KEYCLOAK_URL/admin/realms/master/groups

    # New users
    curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" \
        -d '{"username": "dev1", "email": "dev1@solo.io", "firstName": "Dev1", "enabled": true, "groups": ["dev-team"], "emailVerified": true, "credentials": [{"type": "password", "value": "Passwd00", "temporary": false}]}' \
        $KEYCLOAK_URL/admin/realms/master/users

    curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" \
        -d '{"username": "dev2", "email": "dev2@solo.io", "firstName": "Dev2", "enabled": true, "groups": ["dev-team"], "emailVerified": true, "credentials": [{"type": "password", "value": "Passwd00", "temporary": false}]}' \
        $KEYCLOAK_URL/admin/realms/master/users

    curl -H "Authorization: Bearer ${KEYCLOAK_TOKEN}" -X POST -H "Content-Type: application/json" \
        -d '{"username": "ops1", "email": "ops1@solo.io", "firstName": "Ops1", "enabled": true, "groups": ["ops-team"], "emailVerified": true, "credentials": [{"type": "password", "value": "Passwd00", "temporary": false}]}' \
        $KEYCLOAK_URL/admin/realms/master/users
}

install_argocd() {
    print_info "Installing ArgoCD on management cluster"

    local context=$1
    validate_env_var context "Kubernetes context is not set"
    validate_env_var ARGOCD_VERSION "ArgoCD version is not specified as \$ARGOCD_VERSION environment variable"

    helm repo add argo https://argoproj.github.io/argo-helm
    helm repo update argo

    envsubst < <(cat $DIR/argocd/helm-values.yaml) | helm install argocd argo/argo-cd -n gitops \
        --kube-context=${context} \
        --version ${ARGOCD_VERSION} \
        --create-namespace \
        -f -

    kubectl --context ${context} \
        -n gitops wait deploy/argocd-server --for condition=Available=True --timeout=90s

    wait_for_lb_address $context "argocd-server" "gitops"

    kubectl --context ${context} create ns gloo-mesh

    if [[ -z "${EAST_CONTEXT}" || -z "${WEST_CONTEXT}" ]]; then
        error "Kubernetes contexts not set. Please set environment variables, \$EAST_CONTEXT, \$WEST_CONTEXT."
    else
        if command -v argocd &> /dev/null; then
            if argocd login --plaintext argocd.$DOMAIN_NAME:80 --insecure >& /dev/null; then
                argocd cluster add $WEST_CONTEXT -y
                argocd cluster add $EAST_CONTEXT -y
            else
                error "Unable to register the worker clusters. Please run the following commands,"
                echo "argocd login --plaintext argocd.$DOMAIN_NAME:80 --insecure"
                echo "argocd cluster add $WEST_CONTEXT"
                echo "argocd cluster add $EAST_CONTEXT"
            fi
        else
            error "ArgoCD CLI command not found"
        fi
    fi
}

install_gitea() {
    print_info "Installing Gitea on management cluster"

    local context=$1

    helm repo add gitea-charts https://dl.gitea.io/charts/
    helm repo update gitea-charts

    envsubst < <(cat $DIR/gitea/helm-values.yaml) | helm install gitea gitea-charts/gitea -n gitops \
        --kube-context=${context} \
        --version ${GITEA_VERSION} \
        --create-namespace \
        -f -

    kubectl --context ${context} \
        -n gitops wait deploy/gitea --for condition=Available=True --timeout=90s

    wait_for_lb_address $context "gitea-http" "gitops"

    # Add the repository
    TOKEN=$(curl -s -XPOST -H "Content-Type: application/json" -k -d '{"name":"Admin API Token"}' -u admin:Passwd00 http://git-ui.$DOMAIN_NAME/api/v1/users/admin/tokens | jq .sha1 | sed -e 's/"//g')
    curl -v -H "content-type: application/json" -H "Authorization: token $TOKEN" -X POST http://git-ui.$DOMAIN_NAME/api/v1/user/repos -d '{"name": "gloo-mesh-config", "description": "Gloo Mesh configuration", "private": false}'
}

install_cilium() {
    local context=$1
    local cluster_name=$2
    local cloud_provider=$3
    local cluster_region=$4

    print_info "Installing Cilium on ${context} cluster"

    validate_env_var context "Kubernetes context is not set"
    validate_env_var cluster_name "Cluster name not set"
    validate_env_var cloud_provider "Cluster provider not set"
    validate_env_var cluster_region "Cluster region not set"
    validate_env_var CILIUM_VERSION "Cilium version is not specified as \$CILIUM_VERSION environment variable"

    if [[ "${cloud_provider}" != "eks" && "${cloud_provider}" != "eks-ipv6" ]]; then
        error "Currently Cilium chaining is only tested and supported on AWS"
        return
    fi

    local original_scale=$(kubectl --context $context -n kube-system get deploy/coredns -o=jsonpath='{.spec.replicas}')
    kubectl --context $context scale --replicas=0 -n kube-system deploy/coredns

    helm repo add cilium https://helm.cilium.io/
    helm repo update cilium

    if [[ "${cloud_provider}" == "eks" ]]; then
        envsubst < <(cat $DIR/cilium/eks-helm-values.yaml) | helm upgrade --install cilium cilium/cilium -n kube-system \
            --kube-context=${context} \
            --version $CILIUM_VERSION \
            -f -
    elif [[ "${cloud_provider}" == "eks-ipv6" ]]; then
        envsubst < <(cat $DIR/cilium/eks-ipv6-helm-values.yaml) | helm upgrade --install cilium cilium/cilium -n kube-system \
            --kube-context=${context} \
            --version $CILIUM_VERSION \
            -f -
    fi

    kubectl --context $context \
        -n kube-system rollout status --watch daemonset/cilium --timeout=240s

    sleep 10

    kubectl --context $context scale --replicas=$original_scale -n kube-system deploy/coredns
}

install_kafka() {
    local context=$1
    local cluster_name=$2
    local cloud_provider=$3
    local cluster_region=$4

    print_info "Installing Kafka on ${context} cluster"

    validate_env_var context "Kubernetes context is not set"
    validate_env_var cluster_name "Cluster name not set"
    validate_env_var cloud_provider "Cluster provider not set"
    validate_env_var cluster_region "Cluster region not set"
    validate_env_var KAFKA_VERSION "Kafka version is not specified as \$KAFKA_VERSION environment variable"

    install_ebs_csi_driver $context $cluster_name $cloud_provider $cluster_region

    envsubst < <(cat $DIR/kafka/helm-values.yaml) | helm install kafka oci://registry-1.docker.io/bitnamicharts/kafka -n kafka \
        --kube-context ${context} \
        --version ${KAFKA_VERSION} \
        --create-namespace \
        -f -
}

install_ebs_csi_driver() {
    local context=$1
    local cluster_name=$2
    local cloud_provider=$3
    local cluster_region=$4

    print_info "Installing Kafka on ${context} cluster"

    validate_env_var context "Kubernetes context is not set"
    validate_env_var cluster_name "Cluster name not set"
    validate_env_var cloud_provider "Cluster provider not set"
    validate_env_var cluster_region "Cluster region not set"

    if [[ "$cloud_provider" == "eks" || "$cloud_provider" == "eks-ipv6" ]]; then
        local sa_namespace="kube-system"
        local role_name="AmazonEKS_EBS_CSI_DriverRole"
        # Create an IAM OIDC identity provider and attach policy
        # Following is needed for enabling EBS CSI driver
        create_aws_identity_role_and_attach_predefined_policy_for_ebs_csi_driver $context \
            $cluster_name \
            $cluster_region \
            "AmazonEBSCSIDriverPolicy" \
            "${role_name}" \
            "ebs-csi-controller-sa" \
            $sa_namespace
    fi
}

help() {
    cat << EOF
usage: ./provision-integrations.sh
-p | --provider     (Required)      Cloud provider for the cluster (Accepted values: aks, eks, eks-ipv6, gke)
-c | --context      (Required)      Kubernetes context
-n | --name         (Required)      Cluster name (Used for setting up AWS identity)
-s | --services     (Required)      Comma delimited set of services to deploy (Accepted values: alb, argocd, cert_manager, cert_manager_pca, cilium, external_dns, gitea, grafana, keycloak, vault)
-h | --help                         Usage
EOF

    exit 1
}

# Pre-validation
validate_env_var CLUSTER_OWNER "Cluster owner \$CLUSTER_OWNER not set"

supported_services=("alb" "argocd" "cert_manager" "cert_manager_pca" "cilium" "external_dns" "gitea" "grafana" "kafka" "keycloak" "vault" "ebs")

SHORT=p:,c:,n:,s:,h
LONG=provider:,context:,name:,services:,help
OPTS=$(getopt -a -n "provision-integrations.sh" --options $SHORT --longoptions $LONG -- "$@")

VALID_ARGUMENTS=$#

if [ "$VALID_ARGUMENTS" -eq 0 ]; then
  help
fi

eval set -- "$OPTS"

while [ : ]; do
  case "$1" in
    -p | --provider )
      cloud_provider="$2"
      shift 2
      ;;
    -c | --context )
      context="$2"
      shift 2
      ;;
    -n | --name )
      cluster_name="$2"
      shift 2
      ;;
    -s | --services )
      services="$2"
      shift 2
      ;;
    -h | --help)
      help
      ;;
    --)
      shift;
      break
      ;;
    *)
      echo "Unexpected option: $1"
      help
      ;;
  esac
done

validate_var $cloud_provider "Cloud provider not specified"
validate_var $context "Kubernetes context not specified"
validate_var $cluster_name "Cluster name not specified"
validate_var $services "Services list not specified"

if [[ $cloud_provider != "aks" && $cloud_provider != "eks" && $cloud_provider != "eks-ipv6" && $cloud_provider != "gke" ]]; then
    error_exit "Only accepted cloud providers are [aks, eks, eks-ipv6, gke]"
fi

if [[ $cloud_provider == "eks" || $cloud_provider == "eks-ipv6" ]]; then
    validate_env_var EKS_CLUSTER_REGION "EKS cluster region \$EKS_CLUSTER_REGION not set"
elif [[ $cloud_provider == "gke" ]]; then
    validate_env_var GKE_CLUSTER_REGION "GKE cluster region \$GKE_CLUSTER_REGION not set"
fi

# Determine the LB types
export NLB_LB_SCHEME_TYPE="internet-facing"
export NLB_LB_ADDRESS_TYPE="ipv4"
if [[ $cloud_provider == "eks-ipv6" ]]; then
    export NLB_LB_SCHEME_TYPE="internal"
    export NLB_LB_ADDRESS_TYPE="dualstack"
fi

for service in $(echo $services | tr "," "\n")
do
    if [[ ! " ${supported_services[*]} " =~ " ${service} " ]]; then
        error_exit "Service ${service} isnt accepted currently"
    fi

    if [[ "${service}" == "alb" ]]; then
        install_alb_controller $context $cluster_name $cloud_provider $EKS_CLUSTER_REGION
    elif [[ "${service}" == "external_dns" ]]; then
        install_external_dns $context $cluster_name $cloud_provider $EKS_CLUSTER_REGION
    elif [[ "${service}" == "cert_manager" || "${service}" == "cert_manager_pca" ]]; then
        if [[ "${service}" == "cert_manager_pca" ]]; then
            install_cert_manager $context $cluster_name $cloud_provider true $EKS_CLUSTER_REGION
        else
            install_cert_manager $context $cluster_name $cloud_provider false $EKS_CLUSTER_REGION
        fi
    elif [[ "${service}" == "vault" ]]; then
        install_vault $context
    elif [[ "${service}" == "grafana" ]]; then
        install_grafana $context
    elif [[ "${service}" == "keycloak" ]]; then
        install_keycloak $context $cluster_name $cloud_provider $EKS_CLUSTER_REGION
    elif [[ "${service}" == "argocd" ]]; then
        install_argocd $context 
    elif [[ "${service}" == "gitea" ]]; then
        install_gitea $context
    elif [[ "${service}" == "cilium" ]]; then
        install_cilium $context $cluster_name $cloud_provider $EKS_CLUSTER_REGION
    elif [[ "${service}" == "kafka" ]]; then
        install_kafka $context $cluster_name $cloud_provider $EKS_CLUSTER_REGION
    elif [[ "${service}" == "ebs" ]]; then
        install_ebs_csi_driver $context $cluster_name $cloud_provider $EKS_CLUSTER_REGION
    else
        error_exit "Service ${service} isnt recognized"
    fi
done