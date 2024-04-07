# Demo of Solo.io's Gloo Platform - v2.5

Demo of [Gloo Platform](https://docs.solo.io/gloo-mesh-enterprise) version `2.5` features.

## Prerequisites

1. Install tools

    | Command   | Version |      Installation      |
    |:----------|:---------------|:-------------|
    | `helm` | latest | `brew install helm` |
    | `istioctl` | `1.19.5` | `asdf install istioctl 1.19.5` |
    | `meshctl` | `2.5.3` | `curl -sL https://run.solo.io/meshctl/install \| GLOO_MESH_VERSION=v2.5.3 sh -` |
    | Vault | latest | `brew tap hashicorp/tap && brew install hashicorp/tap/vault` |
    | `cfssl` | latest | `brew install cfssl` |
    | `jq` | latest | `brew install jq` |
    | `kustomize` | latest | `brew install kustomize` |
    | `getopt` | latest | `brew install gnu-getopt` |

2. Set up environment variables

    ```
    export GLOO_PLATFORM_VERSION="2.5.3"
    export GLOO_PLATFORM_HELM_VERSION="v${GLOO_PLATFORM_VERSION}"

    export ISTIO_VERSION="1.19.7"
    export ISTIO_HELM_VERSION="${ISTIO_VERSION}"
    export ISTIO_SOLO_VERSION="${ISTIO_VERSION}-solo"
    export ISTIO_SOLO_REPO="us-docker.pkg.dev/gloo-mesh/istio-bf39a24ed9df"
    export REVISION="1-19-7"

    export CILIUM_SOLO_REPO="us-docker.pkg.dev/gloo-mesh/cilium-0e863d71dfa5"
    export CILIUM_VERSION="1.14.5"

    export CERT_MANAGER_VERSION="v1.14.3"
    export VAULT_VERSION="0.27.0"
    export ARGOCD_VERSION="5.55.0"
    export GITEA_VERSION="10.1.3"
    export KAFKA_VERSION="26.4.2"
    ```

3. Provisioning the clusters

    Use `run.sh prov` in either `cloud-provisioner/` projects or `local-provisioner/` to provision a set of clusters.

    For e.g. `cloud-provisioner/eks-multicluster/run.sh prov` to provision a 3 cluster environment on AWS EKS.

## Installation

Deploy Gloo Platform and sub-components using Helm.

```
./install.sh
```

`install.sh` has the following options,

| Alias | Long option | Optional | Description |
|:----------|:-------------|:------|:------|
| -c  | --cilium    |                                 Yes |     Install CNI (Currently in chain mode only)
| -ca | --ca [one of: vault, vault-cm-only, pca] |    Yes |     Enable Vault integration (uses cert-manager for Relay & uses Root Trust Policy configuration for Istio)
| -d  | --dns | Yes | In Addition, to core integrations (`-i` option) add DNS support
| -g  | --gitops        |                             Yes |     In Addition, to core integrations (`-i` option) install GitOps integrations (such as ArgoCD, Gitea)
| -i  | --integrations  |                             Yes |     Install core integrations (By default ALB & cert-manager will be deployed)
| -idp| --idp | Yes | In Addition, to core integrations (`-i` option) install Keycloak
| -l  | --lifecycle     |                             Yes |     Enable life cycle management of Istio and sub-components instead of installing with Helm


## Clean Up

### Gloo Platform Components and Integrations

Perform a clean up of all the installed components.

```
./uninstall.sh
```

`uninstall.sh` has the following options,

| Alias | Long option | Optional | Description |
|:----------|:-------------|:------|:------|
| -i  | --integrations    |                                 Yes |     Removes all the integration components

### Clusters

Use `run.sh clean` script either in `cloud-provisioner/` projects or `local-provisioner/` to destroy the clusters.