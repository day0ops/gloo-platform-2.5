#!/usr/bin/env bash

###################################################################
# Script Name   : install.sh
# Description   : Provision a Gloo Platform environment
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
###################################################################

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/utility/common.sh

prechecks() {
    if [[ -z "${EAST_CONTEXT}" || -z "${WEST_CONTEXT}" || -z "${MGMT_CONTEXT}" ]]; then
        error_exit "Kubernetes contexts not set. Please set environment variables, \$EAST_CONTEXT, \$WEST_CONTEXT, and \$MGMT_CONTEXT."
    fi

    if [[ -z "${EAST_CLOUD_PROVIDER}" || -z "${WEST_CLOUD_PROVIDER}" || -z "${MGMT_CLOUD_PROVIDER}" ]]; then
        error_exit "Cloud provider not set. Please set environment variables, \$EAST_CLOUD_PROVIDER, \$WEST_CLOUD_PROVIDER, and \$MGMT_CLOUD_PROVIDER."
    fi

    if [[ -z "${EAST_MESH_NAME}" || -z "${WEST_MESH_NAME}" || -z "${MGMT_MESH_NAME}" ]]; then
        error_exit "Cluster names are not set. Please set environment variables, \$EAST_MESH_NAME, \$WEST_MESH_NAME, and \$MGMT_MESH_NAME."
    fi

    if [[ -z "${GLOO_PLATFORM_VERSION}" || -z "${GLOO_PLATFORM_HELM_VERSION}" ]]; then
        error_exit "Gloo Platform version is not set. Please set environment variable, \$GLOO_PLATFORM_VERSION."
    fi

    if [[ -z "${ISTIO_VERSION}" || -z "${ISTIO_HELM_VERSION}" || -z "${REVISION}" || -z "${ISTIO_SOLO_VERSION}" || -z "${ISTIO_SOLO_REPO}" ]]; then
        error_exit "Istio version details are not set. Please set environment variables, \$ISTIO_VERSION, \$ISTIO_SOLO_VERSION, \$ISTIO_SOLO_REPO, \$REVISION."
    fi

    if [[ -z "${GLOO_PLATFORM_GLOO_GATEWAY_LICENSE_KEY}" || -z "${GLOO_PLATFORM_GLOO_MESH_LICENSE_KEY}" ]]; then
        error_exit "Gloo Platform license keys are not set. Please set both environment variables, \$GLOO_PLATFORM_GLOO_GATEWAY_LICENSE_KEY & \$GLOO_PLATFORM_GLOO_MESH_LICENSE_KEY"
    fi
}

install_istio() {
    print_info "Installing Istio on all the worker clusters"

    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo update istio

    kubectl --context $WEST_CONTEXT create ns istio-config
    kubectl --context $EAST_CONTEXT create ns istio-config

    debug "Installing Istio base on worker clusters ...."
    envsubst < <(cat $DIR/core/istio/helm/base.yaml) | helm upgrade --install istio-base istio/base \
        --kube-context ${WEST_CONTEXT} \
        --namespace=istio-system \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        -f -
    envsubst < <(cat $DIR/core/istio/helm/base.yaml) | helm upgrade --install istio-base istio/base \
        --kube-context=${EAST_CONTEXT} \
        --namespace=istio-system \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        -f -

    debug "Installing Istio control plane on worker clusters ...."
    CLUSTER_NAME=$WEST_MESH_NAME envsubst < <(cat $DIR/core/istio/helm/istiod.yaml) | helm upgrade --install istiod istio/istiod \
        --kube-context=${WEST_CONTEXT} \
        --namespace=istio-system \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        -f -
    CLUSTER_NAME=$EAST_MESH_NAME envsubst < <(cat $DIR/core/istio/helm/istiod.yaml) | helm upgrade --install istiod istio/istiod \
        --kube-context=${EAST_CONTEXT} \
        --namespace=istio-system \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        -f -
    kubectl --context ${WEST_CONTEXT} \
        -n istio-system wait deploy/istiod-${REVISION} --for condition=Available=True --timeout=90s
    kubectl --context ${EAST_CONTEXT} \
        -n istio-system wait deploy/istiod-${REVISION} --for condition=Available=True --timeout=90s

    debug "Installing Istio ingress gateways on worker clusters ...."
    CLUSTER_NAME=$WEST_MESH_NAME NLB_LB_SCHEME_TYPE=$WEST_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$WEST_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/istio/helm/ingress-gateway-west.yaml) | helm upgrade --install istio-ingressgateway istio/gateway \
        --kube-context=${WEST_CONTEXT} \
        --namespace=istio-ingress \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        --post-renderer $DIR/core/istio/helm/kustomize/gateways/kustomize \
        -f -
    CLUSTER_NAME=$EAST_MESH_NAME NLB_LB_SCHEME_TYPE=$EAST_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$EAST_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/istio/helm/ingress-gateway-east.yaml) | helm upgrade --install istio-ingressgateway istio/gateway \
        --kube-context=${EAST_CONTEXT} \
        --namespace=istio-ingress \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        --post-renderer $DIR/core/istio/helm/kustomize/gateways/kustomize \
        -f -
    kubectl --context ${WEST_CONTEXT} \
        -n istio-ingress wait deploy/istio-ingressgateway-${REVISION} --for condition=Available=True --timeout=90s
    kubectl --context ${EAST_CONTEXT} \
        -n istio-ingress wait deploy/istio-ingressgateway-${REVISION} --for condition=Available=True --timeout=90s

    debug "Installing Istio east/west gateways on worker clusters ...."
    CLUSTER_NAME=$WEST_MESH_NAME NLB_LB_SCHEME_TYPE=$WEST_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$WEST_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/istio/helm/eastwest-gateway.yaml) | helm upgrade --install istio-eastwestgateway istio/gateway \
        --kube-context=${WEST_CONTEXT} \
        --namespace=istio-eastwest \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        --post-renderer $DIR/core/istio/helm/kustomize/gateways/kustomize \
        -f -
    CLUSTER_NAME=$EAST_MESH_NAME NLB_LB_SCHEME_TYPE=$EAST_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$EAST_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/istio/helm/eastwest-gateway.yaml) | helm upgrade --install istio-eastwestgateway istio/gateway \
        --kube-context=${EAST_CONTEXT} \
        --namespace=istio-eastwest \
        --create-namespace \
        --version=${ISTIO_HELM_VERSION} \
        --post-renderer $DIR/core/istio/helm/kustomize/gateways/kustomize \
        -f -
    kubectl --context ${WEST_CONTEXT} \
        -n istio-eastwest wait deploy/istio-eastwestgateway-${REVISION} --for condition=Available=True --timeout=90s
    kubectl --context ${EAST_CONTEXT} \
        -n istio-eastwest wait deploy/istio-eastwestgateway-${REVISION} --for condition=Available=True --timeout=90s
}

install_istio_with_ilm() {
    print_info "Installing Istio on all the worker clusters with ILM"

    debug "Installing Istio control plane ...."
    envsubst < <(cat $DIR/core/istio/ilm/istiod.yaml) | kubectl --context ${MGMT_CONTEXT} apply \
        -n gloo-mesh \
        -f -

    debug "Installing Istio ingress gateways ...."
    NLB_LB_SCHEME_TYPE=$WEST_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$WEST_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/istio/ilm/ingress-gateway.yaml) | kubectl --context ${MGMT_CONTEXT} apply \
        -n gloo-mesh \
        -f -

    debug "Installing Istio east/west gateways ...."
    NLB_LB_SCHEME_TYPE=$EAST_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$EAST_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/istio/ilm/eastwest-gateway.yaml) | kubectl --context ${MGMT_CONTEXT} apply \
        -n gloo-mesh \
        -f -
}

configure_federation() {
    kubectl --context ${MGMT_CONTEXT} apply -f $DIR/core/gloo-platform/self-signed/federation/federated-trust-policy.yaml
}

update_install_with_vault_support() {
    print_info "Updating Istio with Vault support on all the worker clusters"

    # ------ Federation for west cluster
    envsubst < <(cat $DIR/core/gloo-platform/vault/federation/federated-west-mesh-trust-policy.yaml) | kubectl --context ${WEST_CONTEXT} apply -f -
    # Upgrade Istio control plane with Vault sidecars
    CLUSTER_NAME=$WEST_MESH_NAME envsubst < <(cat $DIR/core/istio/helm/istiod.yaml) | helm --kube-context ${WEST_CONTEXT} upgrade istiod istio/istiod \
        -n istio-system \
        --version $ISTIO_HELM_VERSION \
        --post-renderer $DIR/core/istio/helm/kustomize/istiod/kustomize \
        --wait \
        --timeout 5m0s \
        -f -
    sleep 10
    # Restart control plane
    kubectl --context ${WEST_CONTEXT} \
        -n istio-system rollout restart deploy/istiod-${REVISION}
    kubectl --context ${WEST_CONTEXT} \
        -n istio-system rollout status deploy/istiod-${REVISION} --timeout=90s
    sleep 5
    # Restart all the gateways
    kubectl --context ${WEST_CONTEXT} \
        -n istio-ingress rollout restart deploy/istio-ingressgateway-${REVISION}
    kubectl --context ${WEST_CONTEXT} \
        -n istio-eastwest rollout restart deploy/istio-eastwestgateway-${REVISION}
    # And the rest
    kubectl --context ${WEST_CONTEXT} \
        -n gloo-mesh-addons rollout restart deploy/rate-limiter
    kubectl --context ${WEST_CONTEXT} \
        -n gloo-mesh-addons rollout restart deploy/redis
    kubectl --context ${WEST_CONTEXT} \
        -n gloo-mesh-addons rollout restart deploy/ext-auth-service

    # ------ Federation for east cluster
    envsubst < <(cat $DIR/core/gloo-platform/vault/federation/federated-east-mesh-trust-policy.yaml) | kubectl --context ${EAST_CONTEXT} apply -f -
    # Upgrade Istio control plane with Vault sidecars
    CLUSTER_NAME=$EAST_MESH_NAME envsubst < <(cat $DIR/core/istio/helm/istiod.yaml) | helm --kube-context ${EAST_CONTEXT} upgrade istiod istio/istiod \
        -n istio-system \
        --version $ISTIO_HELM_VERSION \
        --post-renderer $DIR/core/istio/helm/kustomize/istiod/kustomize \
        --wait \
        --timeout 5m0s \
        -f -
    sleep 10
    # Restart control plane
    kubectl --context ${EAST_CONTEXT} \
        -n istio-system rollout restart deploy/istiod-${REVISION}
    kubectl --context ${EAST_CONTEXT} \
        -n istio-system rollout status deploy/istiod-${REVISION} --timeout=90s
    sleep 5
    # Restart all the gateways
    kubectl --context ${EAST_CONTEXT} \
        -n istio-ingress rollout restart deploy/istio-ingressgateway-${REVISION}
    kubectl --context ${EAST_CONTEXT} \
        -n istio-eastwest rollout restart deploy/istio-eastwestgateway-${REVISION}
    # And the rest
    kubectl --context ${EAST_CONTEXT} \
        -n gloo-mesh-addons rollout restart deploy/rate-limiter
    kubectl --context ${EAST_CONTEXT} \
        -n gloo-mesh-addons rollout restart deploy/redis
    kubectl --context ${EAST_CONTEXT} \
        -n gloo-mesh-addons rollout restart deploy/ext-auth-service
}

install_gloo_platform() {
    cloud_provider=$1
    should_support_vault=$2

    print_info "Starting to install Gloo Platform"

    helm repo add gloo-platform https://storage.googleapis.com/gloo-platform/helm-charts
    helm repo update gloo-platform

    helm upgrade --install gloo-platform-crds gloo-platform/gloo-platform-crds \
        --kube-context=${MGMT_CONTEXT} \
        --namespace=gloo-mesh \
        --create-namespace \
        --version=${GLOO_PLATFORM_HELM_VERSION}

    if [[ "$should_support_vault" == true ]]; then
        debug "Installing Gloo Platform mgmt plane [with Vault support] ...."
        value=\$value NLB_LB_SCHEME_TYPE=$MGMT_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$MGMT_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/gloo-platform/vault/gloo-platform-mgmt-plane.yaml) | helm upgrade --install gloo-platform gloo-platform/gloo-platform \
            --kube-context=${MGMT_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION} \
            -f -
    else
        debug "Installing Gloo Platform mgmt plane ...."
        value=\$value NLB_LB_SCHEME_TYPE=$MGMT_NLB_LB_SCHEME_TYPE NLB_LB_ADDRESS_TYPE=$MGMT_NLB_LB_ADDRESS_TYPE envsubst < <(cat $DIR/core/gloo-platform/self-signed/gloo-platform-mgmt-plane.yaml) | helm upgrade --install gloo-platform gloo-platform/gloo-platform \
            --kube-context=${MGMT_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION} \
            -f -
    fi

    kubectl --context ${MGMT_CONTEXT} \
        -n gloo-mesh wait deploy/gloo-mesh-mgmt-server --for condition=Available=True --timeout=90s

    wait_for_lb_address $MGMT_CONTEXT "gloo-mesh-mgmt-server" "gloo-mesh"
    export GLOO_PLATFORM_MGMT_PLANE_PORT=$(kubectl -n gloo-mesh get service gloo-mesh-mgmt-server --context $MGMT_CONTEXT -o jsonpath='{.spec.ports[?(@.name=="grpc")].port}')
    export ENDPOINT_GLOO_PLATFORM_MGMT_PLANE=$(kubectl --context ${MGMT_CONTEXT} -n gloo-mesh get svc gloo-mesh-mgmt-server -o jsonpath='{.status.loadBalancer.ingress[0].*}'):${GLOO_PLATFORM_MGMT_PLANE_PORT}

    wait_for_lb_address $MGMT_CONTEXT "gloo-telemetry-gateway" "gloo-mesh"
    export GLOO_PLATFORM_TELEMETRY_GATEWAY_PORT=$(kubectl -n gloo-mesh get service gloo-telemetry-gateway --context $MGMT_CONTEXT -o jsonpath='{.spec.ports[?(@.name=="otlp")].port}')
    export ENDPOINT_GLOO_PLATFORM_TELEMETRY_GATEWAY=$(kubectl --context ${MGMT_CONTEXT} -n gloo-mesh get svc gloo-telemetry-gateway -o jsonpath='{.status.loadBalancer.ingress[0].*}'):${GLOO_PLATFORM_TELEMETRY_GATEWAY_PORT}

    kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: KubernetesCluster
metadata:
  name: ${EAST_MESH_NAME}
  namespace: gloo-mesh
spec:
  clusterDomain: cluster.local
EOF

    kubectl apply --context ${MGMT_CONTEXT} -f- <<EOF
apiVersion: admin.gloo.solo.io/v2
kind: KubernetesCluster
metadata:
  name: ${WEST_MESH_NAME}
  namespace: gloo-mesh
spec:
  clusterDomain: cluster.local
EOF

    if [[ "$should_support_vault" == false ]]; then
        mkdir -p $DIR/._output/gm

        kubectl --context ${MGMT_CONTEXT} get secret relay-root-tls-secret -n gloo-mesh -o jsonpath='{.data.ca\.crt}' | base64 -d >$DIR/._output/gm/ca.crt
        kubectl --context ${MGMT_CONTEXT} get secret relay-identity-token-secret -n gloo-mesh -o jsonpath='{.data.token}' | base64 -d >$DIR/._output/gm/token

        kubectl --context ${EAST_CONTEXT} create ns gloo-mesh
        kubectl --context ${EAST_CONTEXT} create secret generic relay-root-tls-secret -n gloo-mesh --from-file ca.crt=$DIR/._output/gm/ca.crt
        kubectl --context ${EAST_CONTEXT} create secret generic relay-identity-token-secret -n gloo-mesh --from-file token=$DIR/._output/gm/token

        kubectl --context ${WEST_CONTEXT} create ns gloo-mesh
        kubectl --context ${WEST_CONTEXT} create secret generic relay-root-tls-secret -n gloo-mesh --from-file ca.crt=$DIR/._output/gm/ca.crt
        kubectl --context ${WEST_CONTEXT} create secret generic relay-identity-token-secret -n gloo-mesh --from-file token=$DIR/._output/gm/token

        rm -f $DIR/._output/gm/ca.crt
        rm -f $DIR/._output/gm/token
    fi

    if [[ "$should_support_vault" == true ]]; then
        debug "Installing Gloo Platform agents on worker clusters [with Vault support] ...."
        helm upgrade --install gloo-platform-crds gloo-platform/gloo-platform-crds \
            --kube-context=${EAST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION}
        envsubst < <(cat $DIR/core/gloo-platform/vault/gloo-platform-agent.yaml) | helm upgrade --install gloo-platform-agent gloo-platform/gloo-platform \
            --kube-context=${EAST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION} \
            --set common.cluster=${EAST_MESH_NAME} \
            --set telemetryCollector.config.exporters.otlp.endpoint=${ENDPOINT_GLOO_PLATFORM_TELEMETRY_GATEWAY} \
            -f -
        kubectl --context ${EAST_CONTEXT} \
            -n gloo-mesh wait deploy/gloo-mesh-agent --for condition=Available=True --timeout=90s

        helm upgrade --install gloo-platform-crds gloo-platform/gloo-platform-crds \
            --kube-context=${WEST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION}
        envsubst < <(cat $DIR/core/gloo-platform/vault/gloo-platform-agent.yaml) | helm upgrade --install gloo-platform-agent gloo-platform/gloo-platform \
            --kube-context=${WEST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION} \
            --set common.cluster=${WEST_MESH_NAME} \
            -f -
        kubectl --context ${WEST_CONTEXT} \
            -n gloo-mesh wait deploy/gloo-mesh-agent --for condition=Available=True --timeout=90s
    else
        debug "Installing Gloo Platform agents on worker clusters ...."
        helm upgrade --install gloo-platform-crds gloo-platform/gloo-platform-crds \
            --kube-context=${EAST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION}
        envsubst < <(cat $DIR/core/gloo-platform/self-signed/gloo-platform-agent.yaml) | helm upgrade --install gloo-platform-agent gloo-platform/gloo-platform \
            --kube-context=${EAST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION} \
            --set common.cluster=${EAST_MESH_NAME} \
            -f -
        kubectl --context ${EAST_CONTEXT} \
            -n gloo-mesh wait deploy/gloo-mesh-agent --for condition=Available=True --timeout=90s

        helm upgrade --install gloo-platform-crds gloo-platform/gloo-platform-crds \
            --kube-context=${WEST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION}
        envsubst < <(cat $DIR/core/gloo-platform/self-signed/gloo-platform-agent.yaml) | helm upgrade --install gloo-platform-agent gloo-platform/gloo-platform \
            --kube-context=${WEST_CONTEXT} \
            --namespace=gloo-mesh \
            --create-namespace \
            --version=${GLOO_PLATFORM_HELM_VERSION} \
            --set common.cluster=${WEST_MESH_NAME} \
            --set telemetryCollector.config.exporters.otlp.endpoint=${ENDPOINT_GLOO_PLATFORM_TELEMETRY_GATEWAY} \
            -f -
        kubectl --context ${WEST_CONTEXT} \
            -n gloo-mesh wait deploy/gloo-mesh-agent --for condition=Available=True --timeout=90s
    fi

    debug "Installing Gloo Platform addons on worker clusters ...."
    kubectl --context ${EAST_CONTEXT} create namespace gloo-mesh-addons
    kubectl --context ${EAST_CONTEXT} label namespace gloo-mesh-addons istio.io/rev=$REVISION --overwrite
    kubectl --context ${WEST_CONTEXT} create namespace gloo-mesh-addons
    kubectl --context ${WEST_CONTEXT} label namespace gloo-mesh-addons istio.io/rev=$REVISION --overwrite

    helm upgrade --install gloo-platform-agent-addons gloo-platform/gloo-platform \
        --kube-context=${EAST_CONTEXT} \
        --namespace gloo-mesh-addons \
        --version=${GLOO_PLATFORM_HELM_VERSION} \
        --set common.cluster=${EAST_MESH_NAME} \
        --set rateLimiter.enabled=true \
        --set extAuthService.enabled=true

    helm upgrade --install gloo-platform-agent-addons gloo-platform/gloo-platform \
        --kube-context=${WEST_CONTEXT} \
        --namespace gloo-mesh-addons \
        --version=${GLOO_PLATFORM_HELM_VERSION} \
        --set common.cluster=${WEST_MESH_NAME} \
        --set rateLimiter.enabled=true \
        --set extAuthService.enabled=true
}

help() {
    cat <<EOF
usage: ./`basename $0`

-c  | --cilium                                          (Optional)      Install CNI in chain mode
-ca | --ca [one of: vault, vault-cm-only, pca, spire]   (Optional)      Enable Vault integration (uses cert-manager for Relay & uses Root Trust Policy configuration for Istio)
-d  | --dns                                             (Optional)      Add DNS support
-g  | --gitops                                          (Optional)      Install GitOps integrations
-i  | --integrations                                    (Optional)      Install core integrations
-idp| --idp                                             (Optional)      Integrates Keycloak
-l  | --lifecycle                                       (Optional)      Enable life cycle management of Istio and sub-components instead of installing with Helm
--ignore-gloo                                           (Optional)      Don't install Gloo Platform
--ignore-istio                                          (Optional)      Don't install Istio
-h  | --help                                            Usage
EOF

    exit 1
}

# Create a temp dir (for any internally generated files)
mkdir -p $DIR/._output

# Run prechecks to begin with
prechecks

should_deploy_idp_integrations=false
should_deploy_dns_integrations=false
should_deploy_gitops_integrations=false
should_deploy_integrations=false
should_support_vault=false
should_support_vault_cm_only=false
should_support_pca=false
should_support_spire=false
should_use_ilm=false
should_support_cilium=false
dont_install_gloo=false
dont_install_istio=false

SHORT=c,ca:,d,g,i,idp,l,h
LONG=auth,cilium,ca:,dns,gitops,idp,integrations,lifecycle,ignore-gloo,ignore-istio,help
OPTS=$(getopt -q -a -n "install.sh" --options $SHORT --longoptions $LONG -- "$@")
if [[ $? -ne 0 ]]; then
    echo -e "Unrecognized option provided, check help below\n"
    help
fi

eval set -- "$OPTS"

while [ : ]; do
    case "$1" in
    -c | --cilium)
        should_support_cilium=true
        shift
        ;;
    -ca | --ca)
        ca_type=$2
        shift 2
        if [[ "$ca_type" == "vault" ]]; then
            should_support_vault=true
        elif [[ "$ca_type" == "vault-cm-only" ]]; then
            should_support_vault_cm_only=true
        elif [[ "$ca_type" == "pca" ]]; then
            should_support_pca=true
        elif [[ "$ca_type" == "spire" ]]; then
            should_support_spire=true
        else
            echo "Unknown CA type: '$ca_type', only accepted values are one of: vault, vault-cm-only, pca"
            help
        fi
        ;;
    -d | --dns)
        should_deploy_dns_integrations=true
        shift
        ;;
    -idp | --idp)
        should_deploy_idp_integrations=true
        shift
        ;;
    -i | --integrations)
        should_deploy_integrations=true
        shift
        ;;
    -g | --gitops)
        should_deploy_gitops_integrations=true
        shift
        ;;
    -l | --lifecycle)
        should_use_ilm=true
        shift
        ;;
    --ignore-gloo)
        dont_install_gloo=true
        shift
        ;;
    --ignore-istio)
        dont_install_istio=true
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

print_logo "fg-blue" "🖥  Gloo Platform $GLOO_PLATFORM_VERSION Demo 🖥"

header="Deploying Gloo Platform"
if [[ "$should_support_vault" == true ]]; then
    header+=", with Vault support (uses cert-manager for Relay & uses Root Trust Policy configuration for Istio)"
elif [[ "$should_support_vault_cm_only" == true ]]; then
    header+=", with Vault support (using cert-manager for both Istio & Relay)"
fi
if [[ "$should_support_pca" == true ]]; then
    header+=", with AWS PCA support (using cert-manager for both Istio & Relay)"
fi
if [[ "$should_use_ilm" == true && "$dont_install_istio" != true ]]; then
    header+=", with ILM/GLM support"
fi
if [[ "$should_support_cilium" == true ]]; then
    header+=", with Cilium support"
fi
logger i:8 "${header}" "#" "fg-yellow"

if [[ "$should_support_vault" == true && "$should_use_ilm" == true ]]; then
    error_exit "Vault CA integration is not supported when installing Istio with ILM"
fi

if [[ ("$should_support_pca" == true) && ("$EAST_CLOUD_PROVIDER" != "eks" || "$WEST_CLOUD_PROVIDER" != "eks" || "$MGMT_CLOUD_PROVIDER" != "eks") ]]; then
    error_exit "PCA CA integration is only available when all 3 clusters are hosted on AWS"
fi

if [[ "$should_support_cilium" == true ]]; then
    $DIR/integrations/provision-integrations.sh -p $EAST_CLOUD_PROVIDER -c $EAST_CONTEXT -n $EAST_CLUSTER -s cilium
    $DIR/integrations/provision-integrations.sh -p $WEST_CLOUD_PROVIDER -c $WEST_CONTEXT -n $WEST_CLUSTER -s cilium

    # Give it sometime for things to come up
    sleep 10
fi

if [[ "$should_deploy_integrations" == true ]]; then
    $DIR/integrations/provision-integrations.sh -p $EAST_CLOUD_PROVIDER -c $EAST_CONTEXT -n $EAST_CLUSTER -s alb,ebs
    $DIR/integrations/provision-integrations.sh -p $WEST_CLOUD_PROVIDER -c $WEST_CONTEXT -n $WEST_CLUSTER -s alb,ebs
    $DIR/integrations/provision-integrations.sh -p $MGMT_CLOUD_PROVIDER -c $MGMT_CONTEXT -n $MGMT_CLUSTER -s alb,ebs
    if [[ "$should_support_pca" == true ]]; then
        $DIR/integrations/provision-integrations.sh -p $EAST_CLOUD_PROVIDER -c $EAST_CONTEXT -n $EAST_CLUSTER -s cert_manager_pca
        $DIR/integrations/provision-integrations.sh -p $WEST_CLOUD_PROVIDER -c $WEST_CONTEXT -n $WEST_CLUSTER -s cert_manager_pca
        $DIR/integrations/provision-integrations.sh -p $MGMT_CLOUD_PROVIDER -c $MGMT_CONTEXT -n $MGMT_CLUSTER -s cert_manager_pca
    else
        $DIR/integrations/provision-integrations.sh -p $EAST_CLOUD_PROVIDER -c $EAST_CONTEXT -n $EAST_CLUSTER -s cert_manager
        $DIR/integrations/provision-integrations.sh -p $WEST_CLOUD_PROVIDER -c $WEST_CONTEXT -n $WEST_CLUSTER -s cert_manager
        $DIR/integrations/provision-integrations.sh -p $MGMT_CLOUD_PROVIDER -c $MGMT_CONTEXT -n $MGMT_CLUSTER -s cert_manager
    fi
    if [[ "$should_deploy_dns_integrations" == true ]]; then
        $DIR/integrations/provision-integrations.sh -p $EAST_CLOUD_PROVIDER -c $EAST_CONTEXT -n $EAST_CLUSTER -s external_dns
        $DIR/integrations/provision-integrations.sh -p $WEST_CLOUD_PROVIDER -c $WEST_CONTEXT -n $WEST_CLUSTER -s external_dns
        $DIR/integrations/provision-integrations.sh -p $MGMT_CLOUD_PROVIDER -c $MGMT_CONTEXT -n $MGMT_CLUSTER -s external_dns
    fi
    if [[ "$should_deploy_gitops_integrations" == true ]]; then
        $DIR/integrations/provision-integrations.sh -p $MGMT_CLOUD_PROVIDER -c $MGMT_CONTEXT -n $MGMT_CLUSTER -s argocd
    fi
    if [[ "$should_deploy_idp_integrations" == true ]]; then
        if [[ "$should_deploy_dns_integrations" == false ]]; then
            error_exit "Keycloak IDP currently requires enabling --dns option"
        fi
        $DIR/integrations/provision-integrations.sh -p $MGMT_CLOUD_PROVIDER -c $MGMT_CONTEXT -n $MGMT_CLUSTER -s keycloak
    fi
fi

export MGMT_NLB_LB_SCHEME_TYPE="internet-facing"
export MGMT_NLB_LB_ADDRESS_TYPE="ipv4"
if [[ $MGMT_CLOUD_PROVIDER == "eks-ipv6" ]]; then
    export MGMT_NLB_LB_SCHEME_TYPE="internal"
    export MGMT_NLB_LB_ADDRESS_TYPE="dualstack"
    # If any of the worker clusters are non-ipv6 wel assume its a public LB
    if [[ $WEST_CLOUD_PROVIDER != "eks-ipv6" || $EAST_CLOUD_PROVIDER != "eks-ipv6" ]]; then
        export MGMT_NLB_LB_SCHEME_TYPE="internet-facing"
    fi
fi
export WEST_NLB_LB_SCHEME_TYPE="internet-facing"
export WEST_NLB_LB_ADDRESS_TYPE="ipv4"
if [[ $WEST_CLOUD_PROVIDER == "eks-ipv6" ]]; then
    export WEST_NLB_LB_ADDRESS_TYPE="dualstack"
fi
export EAST_NLB_LB_SCHEME_TYPE="internet-facing"
export EAST_NLB_LB_ADDRESS_TYPE="ipv4"
if [[ $EAST_CLOUD_PROVIDER == "eks-ipv6" ]]; then
    export EAST_NLB_LB_ADDRESS_TYPE="dualstack"
fi

if [[ "$should_support_vault" == true || "$should_support_vault_cm_only" == true ]]; then
    $DIR/integrations/provision-integrations.sh -p $MGMT_CLOUD_PROVIDER -c $MGMT_CONTEXT -n $MGMT_CLUSTER -s vault

    if [[ -f $DIR/._output/vault_env.sh ]]; then
        source $DIR/._output/vault_env.sh
    else
        error_exit "Unable to find 'vault_env.sh'"
    fi

    if [[ "$should_support_vault" == true || "$should_support_vault_cm_only" == true ]]; then
        $DIR/core/pki/vault-bootstrap-relay-ca-gen.sh gen
    elif [[ "$should_support_vault_cm_only" == true ]]; then
        $DIR/core/pki/vault-bootstrap-istio-ca-cert-manager-gen.sh gen
    fi
fi

if [[ "$should_use_ilm" == false && "$dont_install_istio" != true ]]; then
    install_istio
fi

if [[ "$should_support_vault" == true || "$should_support_vault_cm_only" == true ]]; then
    if [[ -f $DIR/._output/vault_env.sh ]]; then
        source $DIR/._output/vault_env.sh
    else
        error_exit "Unable to find 'vault_env.sh'"
    fi

    if [[ "$should_support_vault" == true ]]; then
        $DIR/core/pki/vault-bootstrap-istio-ca-gen.sh gen
    elif [[ "$should_support_vault_cm_only" == true ]]; then
        $DIR/core/pki/vault-bootstrap-istio-ca-cert-manager-gen.sh gen
    fi
fi

if [[ "$dont_install_gloo" != true ]]; then
    install_gloo_platform $MGMT_CLOUD_PROVIDER $should_support_vault
fi

if [[ "$should_use_ilm" == true && "$dont_install_istio" != true && "$dont_install_gloo" != true ]]; then
    sleep 5
    install_istio_with_ilm
fi

sleep 10

if [[ "$should_support_vault" == true && "$dont_install_istio" != true ]]; then
    update_install_with_vault_support
else
    if [[ "$dont_install_istio" != true ]]; then
        # Federate with self service CA
        configure_federation
    fi
fi

print_color_info "🎉 Installation complete 🎉" "fg-green"