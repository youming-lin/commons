#!/bin/bash
# uncomment to debug the script
# set -x
# copy the script below into your app code repo (e.g. ./scripts/check_health.sh) and 'source' it from your pipeline job
#    source ./scripts/check_health.sh
# alternatively, you can source it from online script:
#    source <(curl -sSL "https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_health.sh")
# ------------------
# source: https://raw.githubusercontent.com/open-toolchain/commons/master/scripts/check_health.sh
# Check liveness and readiness probes to confirm application is healthy
# Input env variables (can be received via a pipeline environment properties.file.
echo "IMAGE_NAME=${IMAGE_NAME}"
echo "IMAGE_TAG=${IMAGE_TAG}"
echo "IMAGE_MANIFEST_SHA=${IMAGE_MANIFEST_SHA}"
echo "REGISTRY_URL=${REGISTRY_URL}"
echo "REGISTRY_NAMESPACE=${REGISTRY_NAMESPACE}"
echo "CLUSTER_NAMESPACE=${CLUSTER_NAMESPACE}"
echo "APP_URL=${APP_URL}"

# if IMAGE URL not set in enviroment. Fall back to using image tag
if [ -z "${IMAGE}" ]; then
  IMAGE="${REGISTRY_URL}/${REGISTRY_NAMESPACE}/${IMAGE_NAME}:${IMAGE_TAG}"
fi
if [ -z "${APP_URL}" ]; then
  echo "APP_URL env variable not set. Skipping health check !"
  exit 0
fi
echo "IMAGE=${IMAGE}"
# If custom cluster credentials available, connect to this cluster instead
if [ ! -z "${KUBERNETES_MASTER_ADDRESS}" ]; then
  kubectl config set-cluster custom-cluster --server=https://${KUBERNETES_MASTER_ADDRESS}:${KUBERNETES_MASTER_PORT} --insecure-skip-tls-verify=true
  kubectl config set-credentials sa-user --token="${KUBERNETES_SERVICE_ACCOUNT_TOKEN}"
  kubectl config set-context custom-context --cluster=custom-cluster --user=sa-user --namespace="${CLUSTER_NAMESPACE}"
  kubectl config use-context custom-context
fi
# Use kubectl auth to check if the kubectl client configuration is appropriate
# check if the current configuration can create a deployment in the target namespace
echo "Check ability to get a kubernetes deployment in ${CLUSTER_NAMESPACE} using kubectl CLI"
kubectl auth can-i get deployment --namespace ${CLUSTER_NAMESPACE}

# Ensure that the image match the repository, image name and tag without the @ sha id part to handle
# case when image is sha-suffixed or not - ie:
# us.icr.io/sample/hello-containers-20190823092122682:1-master-a15bd262-20190823100927
# or
# us.icr.io/sample/hello-containers-20190823092122682:1-master-a15bd262-20190823100927@sha256:9b56a4cee384fa0e9939eee5c6c0d9912e52d63f44fa74d1f93f3496db773b2e
CONTAINERS_JSON=$(kubectl get deployments --namespace ${CLUSTER_NAMESPACE} -o json | jq -r '.items[].spec.template.spec.containers[]? | select(.image | test("'"${IMAGE}"'(@.+|$)"))')
echo $CONTAINERS_JSON | jq .

LIVENESS_PROBE_PATH=$(echo $CONTAINERS_JSON | jq -r ".livenessProbe.httpGet.path" | head -n 1)
echo "LIVENESS_PROBE_PATH .$LIVENESS_PROBE_PATH."
# LIVENESS_PROBE_PORT=$(echo $CONTAINERS_JSON | jq -r ".livenessProbe.httpGet.port" | head -n 1)
if [ ${LIVENESS_PROBE_PATH} != null ]; then
  LIVENESS_PROBE_URL=${APP_URL}${LIVENESS_PROBE_PATH}

  # command to get HTTP code from curl with help from https://superuser.com/a/1176569
  if [ "$(curl -isL ${LIVENESS_PROBE_URL} --connect-timeout 3 --max-time 5 --retry 2 --retry-max-time 30 -o /dev/null -w '%{http_code}')" == "200" ]; then
    echo "Successfully reached liveness probe endpoint: ${LIVENESS_PROBE_URL}"
    echo "====================================================================="
  else
    echo "Could not reach liveness probe endpoint: ${LIVENESS_PROBE_URL}"
    exit 1;
  fi
else
  echo "No liveness probe endpoint defined (should be specified in deployment resource)."
fi

READINESS_PROBE_PATH=$(echo $CONTAINERS_JSON | jq -r ".readinessProbe.httpGet.path" | head -n 1)
echo "READINESS_PROBE_PATH .$READINESS_PROBE_PATH."

# READINESS_PROBE_PORT=$(echo $CONTAINERS_JSON | jq -r ".readinessProbe.httpGet.port" | head -n 1)
if [ ${READINESS_PROBE_PATH} != null ]; then
  READINESS_PROBE_URL=${APP_URL}${READINESS_PROBE_PATH}
  # command to get HTTP code from curl with help from https://superuser.com/a/1176569
  if [ "$(curl -isL ${READINESS_PROBE_URL} --connect-timeout 3 --max-time 5 --retry 2 --retry-max-time 30 -o /dev/null -w '%{http_code}')" == "200" ]; then
    echo "Successfully reached readiness probe endpoint: ${READINESS_PROBE_URL}"
    echo "====================================================================="
  else
    echo "Could not reach readiness probe endpoint: ${READINESS_PROBE_URL}"
    exit 1;
  fi
else
  echo "No readiness probe endpoint defined (should be specified in deployment resource)."
fi
