#!/bin/bash
BASE_COLLECTION_PATH="/must-gather"

GITOPS_COLLECTION_PATH="$BASE_COLLECTION_PATH/cluster-gitops"
GITOPS_DIR="$GITOPS_COLLECTION_PATH/gitops"

# Checks if a binary is present on the local system
exit_if_binary_not_installed() {
  for binary in "$@"; do
    command -v "$binary" >/dev/null 2>&1 || {
      echo "Script requires '$binary' command-line utility to be installed on your local machine. Aborting must-gather..." >> "${GITOPS_DIR}"/must-gather-script-errors.txt 2>&1
      exit 1
    }
  done
}

# Checks if the cluster is an OpenShift cluster, if not logs an error
exit_if_not_openshift() {
  if ! oc version ; then
    echo "Error: The current cluster is not an OpenShift cluster. Aborting must-gather..." >> "${GITOPS_DIR}"/must-gather-script-errors.txt 2>&1
    exit 1
  fi
}


function getNamespaces() {
  local namespaces
  local default="openshift-gitops"
  local clusterScopedInstances
  clusterScopedInstances=$(oc get subs openshift-gitops-operator -n openshift-operators -o json | jq '.spec.config.env[]?|select(.name=="ARGOCD_CLUSTER_CONFIG_NAMESPACES").value' | tr -d '",')
  disableDefaultArgoCDInstanceValue=$(oc get subs openshift-gitops-operator -n openshift-operators -o json | jq '.spec.config.env[]?|select(.name=="DISABLE_DEFAULT_ARGOCD_INSTANCE").value')
  if [[ "$(oc get subs openshift-gitops-operator -n openshift-operators -o jsonpath='{.spec.config.env}')" == "" ]]; then
    namespaces=${default}
  elif [[ "${clusterScopedInstances}" != "" ]]; then
    if [[ "${disableDefaultArgoCDInstanceValue}" == "true" ]]; then
      namespaces+="${clusterScopedInstances}"
    else
      namespaces="${clusterScopedInstances} ${default}"
    fi
  else 
    mkdir -p "$GITOPS_DIR"
    echo "Error: getNamespaces- No gitops instances found, please check your cluster configuration." > "${GITOPS_DIR}"/must-gather-script-errors.yaml 2>&1
  fi

  local argocdInstances
  argocdInstances=$(oc get ArgoCD --all-namespaces -o jsonpath='{.items[*].metadata.namespace}')

  local total
  total="${namespaces} ${argocdInstances}"
  echo "${total}"
  
  NAMESPACES=$(echo "${total}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
  export NAMESPACES
}

function main() {

  echo "Starting GitOps Operator must-gather script..."
  mkdir -p "$GITOPS_DIR"

  exit_if_not_openshift
  exit_if_binary_not_installed "kubectl" "oc"
  getNamespaces

  echo "getting OpenShift Cluster Version..."
  oc version > "${GITOPS_DIR}"/oc-version.txt 

  echo "getting GitOps Operator Subscription..."
  oc get subs openshift-gitops-operator -n openshift-operators > "${GITOPS_DIR}"/subscription.yaml 

  for namespace in ${NAMESPACES}; do
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources

    echo "getting pods in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/pods
    for pod in $(oc get pods -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get pod/"${pod}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/pods/"${pod}".yaml
    done
 
    echo "getting deployments in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/deployments
    for deployment in $(oc get deployments -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get deployment/"${deployment}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/deployments/"${deployment}".yaml
    done

    echo "getting services in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/services
    for service in $(oc get services -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get service/"${service}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/services/"${service}".yaml
    done

    echo "getting replicaSets in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/replicasets
    for replicaset in $(oc get replicasets -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get replicaset/"${replicaset}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/replicasets/"${replicaset}".yaml
    done

    echo "getting statefulsets in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/statefulsets
    for statefulset in $(oc get statefulsets -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get statefulset/"${statefulset}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/statefulsets/"${statefulset}".yaml
    done

    echo "getting routes in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/routes
    for route in $(oc get routes -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get route/"${route}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/routes/"${route}".yaml
    done

    echo "getting ArgoCD in ${namespace}..."
    oc -n "${namespace}" get argocd -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/argocd.yaml

    echo "getting Applications in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/applications
    for application in $(oc get applications.argoproj.io -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get applications.argoproj.io/"${application}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/applications/"${application}".yaml
    done

    local sourceNamespaces
    sourceNamespaces=$(oc get argocd -n "${namespace}" -o jsonpath='{.items[*].spec.sourceNamespaces[*]}' )
    if [[ "${sourceNamespaces}" != "" ]] ; then
      for sourceNamespace in ${sourceNamespaces} ; do 
        local sourceNamespaceApps
        sourceNamespaceApps=$(oc get applications.argoproj.io -n "${sourceNamespace}" -o jsonpath='{ .items[*].metadata.name }' )
        for sourceNamespaceApp in ${sourceNamespaceApps}; do 
          oc -n "${sourceNamespace}" get applications.argoproj.io/"${sourceNamespaceApp}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/applications/"${sourceNamespaceApp}"_sourceNamespace_"${sourceNamespace}".yaml
        done
      done
    fi

    echo "getting ApplicationSets in ${namespace}..."
    mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/applicationsets
    for applicationset in $(oc get applicationset.argoproj.io -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      oc -n "${namespace}" get applicationset.argoproj.io/"${applicationset}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/applicationsets/"${applicationset}".yaml
    done
 
    echo "getting warning events in ${namespace}..."
    oc get events -n openshift-gitops --field-selector type=Warning  > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/warning-events.txt

    echo "getting error events in ${namespace}..."
    oc get events -n openshift-gitops --field-selector type=Error > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/error-events.txt

    # getting logs
    local argoCDName
    argoCDName=$(oc -n "${namespace}" get argocd -o jsonpath='{.items[*].metadata.name}')
    oc logs statefulset/"${argoCDName}"-application-controller -n "${namespace}"  > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/application_controller_logs.txt
    oc logs deployment/"${argoCDName}"-server -n "${namespace}" > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/server_logs.txt
    oc logs deployment/"${argoCDName}"-repo-server -n "${namespace}" > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/repo-server_logs.txt
    oc logs deployment/"${argoCDName}"-redis -n "${namespace}" > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/redis_logs.txt
    oc logs deployment/"${argoCDName}"-dex-server -n "${namespace}" > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/dex-server_logs.txt
  
    local managedNamespaces
    managedNamespaces=$(oc get namespaces --selector=argocd.argoproj.io/managed-by="${namespace}" -o jsonpath='{.items[*].metadata.name}')

    for managedNamespace in ${managedNamespaces}; do

      mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/pods
      for pod in $(oc get pods -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        oc -n "${managedNamespace}" get pod/"${pod}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/pod_"${pod}".yaml
      done

      mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/deployments
      for deployment in $(oc get deployments -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        oc -n "${managedNamespace}" get deployment/"${deployment}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/deployment/"${deployment}".yaml
      done

      mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/services
      for service in $(oc get services -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        oc -n "${managedNamespace}" get service/"${service}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/services/"${service}".yaml
      done

      mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/replicasets
      for replicaset in $(oc get replicasets -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        oc -n "${namespace}" get replicaset/"${replicaset}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/replicasets/"${replicaset}".yaml
      done

      mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/statefulsets
      for statefulset in $(oc get statefulsets -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        oc -n "${managedNamespace}" get statefulset/"${statefulset}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/statefulsets/"${statefulset}".yaml
      done

      mkdir -p "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/routes
      for route in $(oc get routes -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        oc -n "${managedNamespace}" get route/"${route}" -o yaml > "${GITOPS_DIR}"/namespace_"${namespace}"_resources/managedNamespace_"${managedNamespace}"/routes/"${route}".yaml
      done
    done
  done

  echo "getting AppProjects..."
  oc get appProjects.argoproj.io --all-namespaces -o yaml  > "${GITOPS_DIR}"/appprojects.yaml

  echo "getting GitOps CRDs..."
  oc get crds -l operators.coreos.com/openshift-gitops-operator.openshift-operators > "${GITOPS_DIR}"/crds.yaml

  echo "Done! Thank you for using the GitOps must-gather tool :)"
}

# main "$@"
