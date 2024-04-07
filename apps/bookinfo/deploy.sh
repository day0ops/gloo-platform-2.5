#!/usr/bin/env bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/../../utility/common.sh

provision() {
    logger i:8 "Deploying bookinfo on all worker clusters" "=" "fg-yellow"

    # On West Cluster
    kubectl --context ${WEST_CONTEXT} create ns bookinfo-frontends
    kubectl --context ${WEST_CONTEXT} create ns bookinfo-backends
    curl -s https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/bookinfo/platform/kube/bookinfo.yaml | tee bookinfo.yaml
    kubectl --context ${WEST_CONTEXT} label namespace bookinfo-frontends istio.io/rev=$REVISION
    kubectl --context ${WEST_CONTEXT} label namespace bookinfo-backends istio.io/rev=$REVISION
    # Deploy the frontend bookinfo service in the bookinfo-frontends namespace
    kubectl --context ${WEST_CONTEXT} -n bookinfo-frontends apply -f bookinfo.yaml -l 'account in (productpage)'
    kubectl --context ${WEST_CONTEXT} -n bookinfo-frontends apply -f bookinfo.yaml -l 'app in (productpage)'
    # Deploy the backend bookinfo services in the bookinfo-backends namespace for all versions less than v3
    kubectl --context ${WEST_CONTEXT} -n bookinfo-backends apply -f bookinfo.yaml -l 'account in (reviews,ratings,details)'
    kubectl --context ${WEST_CONTEXT} -n bookinfo-backends apply -f bookinfo.yaml -l 'app in (reviews,ratings,details),version notin (v3)'
    # Update the productpage deployment to set the environment variables to define where the backend services are running
    kubectl --context ${WEST_CONTEXT} -n bookinfo-frontends set env deploy/productpage-v1 DETAILS_HOSTNAME=details.bookinfo-backends.svc.cluster.local
    kubectl --context ${WEST_CONTEXT} -n bookinfo-frontends set env deploy/productpage-v1 REVIEWS_HOSTNAME=reviews.bookinfo-backends.svc.cluster.local

    # Update the reviews service to display where it is coming from
    kubectl --context ${WEST_CONTEXT} -n bookinfo-backends set env deploy/reviews-v1 CLUSTER_NAME=${WEST_CONTEXT}
    kubectl --context ${WEST_CONTEXT} -n bookinfo-backends set env deploy/reviews-v2 CLUSTER_NAME=${WEST_CONTEXT}

    provV4Reviews

    # On East Cluster
    kubectl --context ${EAST_CONTEXT} create ns bookinfo-frontends
    kubectl --context ${EAST_CONTEXT} create ns bookinfo-backends
    curl -s https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/bookinfo/platform/kube/bookinfo.yaml | tee bookinfo.yaml
    kubectl --context ${EAST_CONTEXT} label namespace bookinfo-frontends istio.io/rev=$REVISION
    kubectl --context ${EAST_CONTEXT} label namespace bookinfo-backends istio.io/rev=$REVISION
    # Deploy the frontend bookinfo service in the bookinfo-frontends namespace
    kubectl --context ${EAST_CONTEXT} -n bookinfo-frontends apply -f bookinfo.yaml -l 'account in (productpage)'
    kubectl --context ${EAST_CONTEXT} -n bookinfo-frontends apply -f bookinfo.yaml -l 'app in (productpage)'
    # Deploy the backend bookinfo services in the bookinfo-backends namespace for all versions
    kubectl --context ${EAST_CONTEXT} -n bookinfo-backends apply -f bookinfo.yaml -l 'account in (reviews,ratings,details)'
    kubectl --context ${EAST_CONTEXT} -n bookinfo-backends apply -f bookinfo.yaml -l 'app in (reviews,ratings,details)'
    # Update the productpage deployment to set the environment variables to define where the backend services are running
    kubectl --context ${EAST_CONTEXT} -n bookinfo-frontends set env deploy/productpage-v1 DETAILS_HOSTNAME=details.bookinfo-backends.svc.cluster.local
    kubectl --context ${EAST_CONTEXT} -n bookinfo-frontends set env deploy/productpage-v1 REVIEWS_HOSTNAME=reviews.bookinfo-backends.svc.cluster.local
    # Update the reviews service to display where it is coming from
    kubectl --context ${EAST_CONTEXT} -n bookinfo-backends set env deploy/reviews-v1 CLUSTER_NAME=${EAST_CONTEXT}
    kubectl --context ${EAST_CONTEXT} -n bookinfo-backends set env deploy/reviews-v2 CLUSTER_NAME=${EAST_CONTEXT}
    kubectl --context ${EAST_CONTEXT} -n bookinfo-backends set env deploy/reviews-v3 CLUSTER_NAME=${EAST_CONTEXT}

    rm -f bookinfo.yaml
}

provV4Reviews() {
    kubectl --context ${WEST_CONTEXT} -n bookinfo-backends apply -f- <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reviews-v4
  labels:
    app: reviews
    version: v4
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reviews
      version: v4
  template:
    metadata:
      labels:
        app: reviews
        version: v4
    spec:
      serviceAccountName: bookinfo-reviews
      containers:
        - name: reviews
          image: us-central1-docker.pkg.dev/solo-test-236622/jmunozro/examples-bookinfo-reviews-v3:1.16.2
          imagePullPolicy: IfNotPresent
          env:
            - name: LOG_DIR
              value: "/tmp/logs"
            - name: SERVICE_VERSION
              value: "v4"
            - name: STAR_COLOR
              value: "mediumspringgreen"
            - name: RATINGS_HOSTNAME
              value: "ratings.bookinfo-backends.svc.cluster.local"
            - name: CLUSTER_NAME
              value: "${WEST_CONTEXT}"
          ports:
            - containerPort: 9080
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: wlp-output
              mountPath: /opt/ibm/wlp/output
          securityContext:
            runAsUser: 1000
      volumes:
        - name: wlp-output
          emptyDir: {}
        - name: tmp
          emptyDir: {}
EOF

}

delete() {
    if ! confirm "Are you sure you want to proceed with the cleanup ?"; then
        logger i "Ok, existing then ..."
        exit 0
    fi

    kubectl --context ${WEST_CONTEXT} delete ns bookinfo-frontends
    kubectl --context ${WEST_CONTEXT} delete ns bookinfo-backends

    kubectl --context ${EAST_CONTEXT} delete ns bookinfo-frontends
    kubectl --context ${EAST_CONTEXT} delete ns bookinfo-backends
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