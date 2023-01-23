#!/usr/bin/env bash
BASE_COLLECTION_PATH="/must-gather"

if [ "$1" == "--base-collection-path" ]; then
    BASE_COLLECTION_PATH="$2"
    shift 2
fi

GITOPS_COLLECTION_PATH="$BASE_COLLECTION_PATH/cluster-gitops"
GITOPS_DIR="$GITOPS_COLLECTION_PATH/gitops"
ERROR_LOG="${GITOPS_DIR}/must-gather-script-errors.txt"
NO_OUTPUT_LOG="${GITOPS_DIR}/must-gather-script-no-output.txt"
ALL_COMMANDS_LOG="${GITOPS_DIR}/must-gather-script-commands.txt"

ERROR_COUNTER=0
NO_OUTPUT_COUNTER=0

# create_directory creates a directory if it doesn't already exist
# but if the directory already exists, it will log an error and exit
create_directory() {
    local directory="$1"
    if [ -d "$directory" ]; then
        echo "Error: Directory $directory already exists."
        exit 1
    else
        if ! mkdir -p "$directory"; then
            echo "Error: Could not create directory $directory"
            exit 1
        else
            echo " * Directory $directory created successfully"
        fi
    fi
}

# run_and_log executes a command and logs the output to a file "${GITOPS_DIR}" + $2
# If the command fails, it will be retried once
# If the command fails again, the error message will be logged to the ERROR_LOG
run_and_log() {
    local command="$1"
    local output_file="$2"
    local error_file="/tmp/errors.txt"
    local exit_status
    # Save the command to the log file of all commands: $ALL_COMMANDS_LOG
    echo "$command" >> "$ALL_COMMANDS_LOG"

    echo "  - Running: $command"
    # Execute the command and redirect stdout and stderr to files
    if ! $command >"$output_file" 2>"$error_file"; then
        echo "   -> Command failed, retrying..."
        if ! $command >"$output_file" 2>"$error_file"; then
            echo "   -> Command failed again, saving error message to ${ERROR_LOG}"
            # If the error file is empty, log a message to the error file to indicate that there was no output
            # Otherwise, log the contents of the error file
            # This is to avoid logging an empty error message to the error log file (which would be confusing)
            ERROR_COUNTER=$((ERROR_COUNTER + 1))
            if [ ! -s "$error_file" ]; then
              echo "(no output)" >> "$error_file"
            fi

            # Log the error message to the error log file
            {
                echo "------------------------------------------------------------"
                echo "Command: $command"
                echo
                echo "Error: $(cat $error_file)"
                echo "------------------------------------------------------------"
                echo
            } >> "${ERROR_LOG}"

            # Remove the temporary error file, although it will be overwritten on the next run
            # We don't want to leave it around in case the script fails, as it will contain the error message from the last run
            rm "$error_file" || echo "Failed to remove temporary error file: '$error_file'"
            exit_status=1 # Set the exit status to 1 to indicate that the command failed
        fi
    else
        # If the command succeeded, see if the output file is empty
        # If it is, log a message to the output file to indicate that there was no output
        # This is to avoid logging an empty output message to the output file (which would be confusing)
        if [ ! -s "$output_file" ]; then
            echo "   -> No error, but empty output. See all these commands at: '${NO_OUTPUT_LOG}'"
            rm "$output_file" || echo "Failed to remove empty output file: '$output_file'"
            echo "$command" >> "$NO_OUTPUT_LOG"
            NO_OUTPUT_COUNTER=$((NO_OUTPUT_COUNTER + 1))
        else
            echo "   -> Command executed successfully, output saved to $output_file"
            exit_status=0 # Set the exit status to 0 to indicate that the command succeeded
        fi
    fi

    return $exit_status
}


# Checks if a binary is present on the local system, if not logs an error and exits
exit_if_binary_not_installed() {
  for binary in "$@"; do
    command -v "$binary" >/dev/null 2>&1 || {
      run_and_log "command -v \"$binary\""
      echo "Script requires '$binary' command-line utility to be installed on your local machine. Aborting must-gather..."
      exit 1
    }
  done
}

# Checks if the cluster is an OpenShift cluster, if not logs an error and exits
exit_if_not_openshift() {
  local cmd="oc get clusterversion"
  if ! run_and_log "$cmd" "$GITOPS_DIR/clusterversion.txt"; then
    echo "The current cluster is not an OpenShift cluster. Aborting must-gather..."
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

  # Initialize the directory where the must-gather data will be stored and the error log file
  echo "Starting GitOps Operator must-gather script..."
  echo " * Creating directory: '$GITOPS_DIR'"
  create_directory "$GITOPS_DIR"
  echo " * Any errors will be logged to: '$ERROR_LOG'"
  echo " * Any empty output will be logged to: '$NO_OUTPUT_LOG'"

  echo " * Checking for required binaries..."
  exit_if_binary_not_installed "oc" "jq"

  echo " * Checking if the current cluster is an OpenShift cluster..."
  exit_if_not_openshift

  echo " * Checking for GitOps Namespaces..."
  getNamespaces

  echo " * Getting OpenShift Cluster Version..."
  run_and_log "oc version" "$GITOPS_DIR/oc-version.txt"

  echo " * Getting GitOps Operator Subscription..."
  run_and_log "oc get subs openshift-gitops-operator -n openshift-operators -o yaml" "$GITOPS_DIR/subscription.yaml"
  run_and_log "oc get subs openshift-gitops-operator -n openshift-operators -o json" "$GITOPS_DIR/subscription.json"
  run_and_log "oc get subs openshift-gitops-operator -n openshift-operators" "$GITOPS_DIR/subscription.txt"

  for namespace in ${NAMESPACES}; do
    RESOURCES_DIR="${GITOPS_DIR}/namespace_${namespace}_resources"
    create_directory "${RESOURCES_DIR}"

    echo " * Getting pods in ${namespace}..."
    POD_DIR="${RESOURCES_DIR}/pods"
    create_directory "${POD_DIR}"
    run_and_log "oc get pods -n ${namespace}" "${POD_DIR}/pods.txt"
    for pod in $(oc get pods -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get pod/${pod}" "${POD_DIR}/${pod}.txt"
      run_and_log "oc -n ${namespace} get pod/${pod} -o yaml" "${POD_DIR}/${pod}.yaml"
      run_and_log "oc -n ${namespace} get pod/${pod} -o json" "${POD_DIR}/${pod}.json"
    done
 
    echo " * Getting deployments in ${namespace}..."
    DEPLOYMENT_DIR="${RESOURCES_DIR}/deployments"
    create_directory "${DEPLOYMENT_DIR}"
    run_and_log "oc get deployments -n ${namespace}" "${DEPLOYMENT_DIR}/deployments.txt"
    for deployment in $(oc get deployments -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get deployment/${deployment}" "${DEPLOYMENT_DIR}/${deployment}.txt"
      run_and_log "oc -n ${namespace} get deployment/${deployment} -o yaml" "${DEPLOYMENT_DIR}/${deployment}.yaml"
      run_and_log "oc -n ${namespace} get deployment/${deployment} -o json" "${DEPLOYMENT_DIR}/${deployment}.json"
    done

    echo " * Getting services in ${namespace}..."
    SERVICE_DIR="${RESOURCES_DIR}/services"
    create_directory "${SERVICE_DIR}"
    run_and_log "oc get services -n ${namespace}" "${SERVICE_DIR}/services.txt"
    for service in $(oc get services -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get service/${service}" "${SERVICE_DIR}/${service}.txt"
      run_and_log "oc -n ${namespace} get service/${service} -o yaml" "${SERVICE_DIR}/${service}.yaml"
      run_and_log "oc -n ${namespace} get service/${service} -o json" "${SERVICE_DIR}/${service}.json"
    done

    echo " * Getting replicaSets in ${namespace}..."
    REPLICASET_DIR="${RESOURCES_DIR}/replicaSets"
    create_directory "${REPLICASET_DIR}"
    run_and_log "oc get replicasets -n ${namespace}" "${REPLICASET_DIR}/replicaSets.txt"
    for replicaset in $(oc get replicasets -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get replicaset/${replicaset}" "${REPLICASET_DIR}/${replicaset}.txt"
      run_and_log "oc -n ${namespace} get replicaset/${replicaset} -o yaml" "${REPLICASET_DIR}/${replicaset}.yaml"
      run_and_log "oc -n ${namespace} get replicaset/${replicaset} -o json" "${REPLICASET_DIR}/${replicaset}.json"
    done

    echo " * Getting statefulsets in ${namespace}..."
    STATEFULSET_DIR="${RESOURCES_DIR}/statefulsets"
    create_directory "${STATEFULSET_DIR}"
    run_and_log "oc get statefulsets -n ${namespace}" "${STATEFULSET_DIR}/statefulsets.txt"
    for statefulset in $(oc get statefulsets -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get statefulset/${statefulset}" "${STATEFULSET_DIR}/${statefulset}.txt"
      run_and_log "oc -n ${namespace} get statefulset/${statefulset} -o yaml" "${STATEFULSET_DIR}/${statefulset}.yaml"
      run_and_log "oc -n ${namespace} get statefulset/${statefulset} -o json" "${STATEFULSET_DIR}/${statefulset}.json"
    done

    echo " * Getting routes in ${namespace}..."
    ROUTE_DIR="${RESOURCES_DIR}/routes"
    create_directory "${ROUTE_DIR}"
    run_and_log "oc get routes -n ${namespace}" "${ROUTE_DIR}/routes.txt"
    for route in $(oc get routes -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get route/${route}" "${ROUTE_DIR}/${route}.txt"
      run_and_log "oc -n ${namespace} get route/${route} -o yaml" "${ROUTE_DIR}/${route}.yaml"
      run_and_log "oc -n ${namespace} get route/${route} -o json" "${ROUTE_DIR}/${route}.json"
    done

    echo " * Getting ArgoCD in ${namespace}..."
    ARGOCD_DIR="${RESOURCES_DIR}/argocd"
    create_directory "${ARGOCD_DIR}"
    run_and_log "oc get argocd -n ${namespace}" "${ARGOCD_DIR}/argocd.txt"
    for argocd in $(oc get argocd -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get argocd/${argocd}" "${ARGOCD_DIR}/${argocd}.txt"
      run_and_log "oc -n ${namespace} get argocd/${argocd} -o yaml" "${ARGOCD_DIR}/${argocd}.yaml"
      run_and_log "oc -n ${namespace} get argocd/${argocd} -o json" "${ARGOCD_DIR}/${argocd}.json"
    done

    echo " * Getting ArgoCD Applications in ${namespace}..."
    APPLICATION_DIR="${ARGOCD_DIR}/applications"
    create_directory "${APPLICATION_DIR}"
    run_and_log "oc get applications.argoproj.io -n ${namespace}" "${APPLICATION_DIR}/applications.txt"
    for application in $(oc get applications.argoproj.io -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get applications.argoproj.io/${application}" "${APPLICATION_DIR}/${application}.txt"
      run_and_log "oc -n ${namespace} get applications.argoproj.io/${application} -o yaml" "${APPLICATION_DIR}/${application}.yaml"
      run_and_log "oc -n ${namespace} get applications.argoproj.io/${application} -o json" "${APPLICATION_DIR}/${application}.json"
    done


    echo " * Getting ArgoCD Source Namespaces in ${namespace}..."
    local sourceNamespaces
    run_and_log "oc get argocd -n ${namespace} -o jsonpath='{.items[*].spec.sourceNamespaces[*]}'" "${ARGOCD_DIR}/sourceNamespaces.txt"
    sourceNamespaces=$(oc get argocd -n "${namespace}" -o jsonpath='{.items[*].spec.sourceNamespaces[*]}' )
    if [[ "${sourceNamespaces}" != "" ]] ; then
      for sourceNamespace in ${sourceNamespaces} ; do 
        echo " * Getting ArgoCD Applications in ${sourceNamespace}..."
        local sourceNamespaceApps
        SOURCED_DIR="${ARGOCD_DIR}/namespace_${sourceNamespace}_resources/applications"
        run_and_log "oc get applications.argoproj.io -n ${sourceNamespace}" "$SOURCED_DIR/applications.txt"
        sourceNamespaceApps=$(oc get applications.argoproj.io -n "${sourceNamespace}" -o jsonpath='{ .items[*].metadata.name }' )
        for sourceNamespaceApp in ${sourceNamespaceApps}; do 
          run_and_log "oc -n ${sourceNamespace} get applications.argoproj.io/${sourceNamespaceApp}" "${SOURCED_DIR}/${sourceNamespaceApp}.txt"
          run_and_log "oc -n ${sourceNamespace} get applications.argoproj.io/${sourceNamespaceApp} -o yaml" "${SOURCED_DIR}/${sourceNamespaceApp}.yaml"
          run_and_log "oc -n ${sourceNamespace} get applications.argoproj.io/${sourceNamespaceApp} -o json" "${SOURCED_DIR}/${sourceNamespaceApp}.json"
        done
      done
    fi

    echo " * Getting ArgoCD ApplicationSets in ${namespace}..."
    APPLICATIONSETS_DIR="${ARGOCD_DIR}/applicationsets"
    create_directory "${APPLICATIONSETS_DIR}"
    run_and_log "oc get applicationsets.argoproj.io -n ${namespace}" "${APPLICATIONSETS_DIR}/applicationsets.txt"
    for applicationset in $(oc get applicationsets.argoproj.io -n "${namespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
      run_and_log "oc -n ${namespace} get applicationsets.argoproj.io/${applicationset}" "${APPLICATIONSETS_DIR}/${applicationset}.txt"
      run_and_log "oc -n ${namespace} get applicationsets.argoproj.io/${applicationset} -o yaml" "${APPLICATIONSETS_DIR}/${applicationset}.yaml"
      run_and_log "oc -n ${namespace} get applicationsets.argoproj.io/${applicationset} -o json" "${APPLICATIONSETS_DIR}/${applicationset}.json"
    done
 
    echo " * Getting warning events in ${namespace}..."
    EVENTS_DIR="${RESOURCES_DIR}/events"
    create_directory "${EVENTS_DIR}"
    run_and_log "oc get events -n ${namespace} --field-selector type=Warning" "${EVENTS_DIR}/warning-events.txt"
    echo " * Getting error events in ${namespace}..."
    run_and_log "oc get events -n ${namespace} --field-selector type=Error" "${EVENTS_DIR}/error-events.txt"
    echo " * Getting all events in ${namespace}..."
    run_and_log "oc get events -n ${namespace}" "${EVENTS_DIR}/all-events.txt"

    echo " * Getting ArgoCD logs in ${namespace}..."
    ARGOCD_LOG_DIR="${ARGOCD_DIR}/logs"
    create_directory "${ARGOCD_LOG_DIR}"
    local argoCDName
    argoCDName=$(oc -n "${namespace}" get argocd -o jsonpath='{.items[*].metadata.name}')
    run_and_log "oc logs statefulset/${argoCDName}-application-controller -n ${namespace}" "${ARGOCD_LOG_DIR}/application-controller-logs.txt"
    run_and_log "oc logs deployment/${argoCDName}-server -n ${namespace}" "${ARGOCD_LOG_DIR}/server-logs.txt"
    run_and_log "oc logs deployment/${argoCDName}-repo-server -n ${namespace}" "${ARGOCD_LOG_DIR}/repo-server-logs.txt"
    run_and_log "oc logs deployment/${argoCDName}-redis -n ${namespace}" "${ARGOCD_LOG_DIR}/redis-logs.txt"
    run_and_log "oc logs deployment/${argoCDName}-dex-server -n ${namespace}" "${ARGOCD_LOG_DIR}/dex-server-logs.txt"
  
    echo " * Getting ArgoCD Managed namespaces in ${namespace}..."
    run_and_log "oc get namespaces --selector=argocd.argoproj.io/managed-by=${namespace}" "${ARGOCD_DIR}/managed-namespaces.txt"
    local managedNamespaces
    managedNamespaces=$(oc get namespaces --selector=argocd.argoproj.io/managed-by="${namespace}" -o jsonpath='{.items[*].metadata.name}')

    for managedNamespace in ${managedNamespaces}; do
      MANAGED_RESOURCES_DIR="${GITOPS_DIR}/managedNamespace_${managedNamespace}/resources"
      create_directory "${MANAGED_RESOURCES_DIR}"

      echo " * Getting Pods for ArgoCD Managed namespace ${managedNamespace}..."
      MANAGED_RESOURCES_PODS_DIR="${MANAGED_RESOURCES_DIR}/pods"
      create_directory "${MANAGED_RESOURCES_PODS_DIR}"
      run_and_log "oc get pods -n ${managedNamespace}" "${MANAGED_RESOURCES_PODS_DIR}/pods.txt"
      for pod in $(oc get pods -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        run_and_log "oc -n ${managedNamespace} get pod/${pod}" "${MANAGED_RESOURCES_PODS_DIR}/${pod}.txt"
        run_and_log "oc -n ${managedNamespace} get pod/${pod} -o yaml" "${MANAGED_RESOURCES_PODS_DIR}/${pod}.yaml"
        run_and_log "oc -n ${managedNamespace} logs pod/${pod}" "${MANAGED_RESOURCES_PODS_DIR}/${pod}-logs.txt"
      done

      echo " * Getting Deployments for ArgoCD Managed namespace ${managedNamespace}..."
      MANAGED_RESOURCES_DEPLOYMENTS_DIR="${MANAGED_RESOURCES_DIR}/deployments"
      create_directory "${MANAGED_RESOURCES_DEPLOYMENTS_DIR}"
      run_and_log "oc get deployments -n ${managedNamespace}" "${MANAGED_RESOURCES_DEPLOYMENTS_DIR}/deployments.txt"
      for deployment in $(oc get deployments -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        run_and_log "oc -n ${managedNamespace} get deployment ${deployment}" "${MANAGED_RESOURCES_DEPLOYMENTS_DIR}/${deployment}.txt"
        run_and_log "oc -n ${managedNamespace} get deployment/${deployment} -o yaml" "${MANAGED_RESOURCES_DEPLOYMENTS_DIR}/${deployment}.yaml"
        run_and_log "oc -n ${managedNamespace} get deployment/${deployment} -o json" "${MANAGED_RESOURCES_DEPLOYMENTS_DIR}/${deployment}.json"
      done

      echo " * Getting Services for ArgoCD Managed namespace ${managedNamespace}..."
      MANAGED_RESOURCES_SERVICES_DIR="${MANAGED_RESOURCES_DIR}/services"
      create_directory "${MANAGED_RESOURCES_SERVICES_DIR}"
      run_and_log "oc get services -n ${managedNamespace}" "${MANAGED_RESOURCES_SERVICES_DIR}/services.txt"
      for service in $(oc get services -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        run_and_log "oc -n ${managedNamespace} get service/${service}" "${MANAGED_RESOURCES_SERVICES_DIR}/${service}.txt"
        run_and_log "oc -n ${managedNamespace} get service/${service} -o yaml" "${MANAGED_RESOURCES_SERVICES_DIR}/${service}.yaml"
        run_and_log "oc -n ${managedNamespace} get service/${service} -o json" "${MANAGED_RESOURCES_SERVICES_DIR}/${service}.json"
      done

      echo " * Getting Routes for ArgoCD Managed namespace ${managedNamespace}..."
      MANAGED_RESOURCES_ROUTES_DIR="${MANAGED_RESOURCES_DIR}/routes"
      create_directory "${MANAGED_RESOURCES_ROUTES_DIR}"
      run_and_log "oc get routes -n ${managedNamespace}" "${MANAGED_RESOURCES_ROUTES_DIR}/routes.txt"
      for route in $(oc get routes -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        run_and_log "oc -n ${managedNamespace} get route/${route}" "${MANAGED_RESOURCES_ROUTES_DIR}/${route}.txt"
        run_and_log "oc -n ${managedNamespace} get route/${route} -o yaml" "${MANAGED_RESOURCES_ROUTES_DIR}/${route}.yaml"
        run_and_log "oc -n ${managedNamespace} get route/${route} -o json" "${MANAGED_RESOURCES_ROUTES_DIR}/${route}.json"
      done

      echo " * Getting ReplicaSets for ArgoCD Managed namespace ${managedNamespace}..."
      MANAGED_RESOURCES_REPLICASETS_DIR="${MANAGED_RESOURCES_DIR}/replicasets"
      create_directory "${MANAGED_RESOURCES_REPLICASETS_DIR}"
      run_and_log "oc get replicasets -n ${managedNamespace}" "${MANAGED_RESOURCES_REPLICASETS_DIR}/replicasets.txt"
      for replicaset in $(oc get replicasets -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        run_and_log "oc -n ${managedNamespace} get replicaset/${replicaset}" "${MANAGED_RESOURCES_REPLICASETS_DIR}/${replicaset}.txt"
        run_and_log "oc -n ${managedNamespace} get replicaset/${replicaset} -o yaml" "${MANAGED_RESOURCES_REPLICASETS_DIR}/${replicaset}.yaml"
        run_and_log "oc -n ${managedNamespace} get replicaset/${replicaset} -o json" "${MANAGED_RESOURCES_REPLICASETS_DIR}/${replicaset}.json"
      done

      echo " * Getting StatefulSets for ArgoCD Managed namespace ${managedNamespace}..."
      MANAGED_RESOURCES_STATEFULSETS_DIR="${MANAGED_RESOURCES_DIR}/statefulsets"
      create_directory "${MANAGED_RESOURCES_STATEFULSETS_DIR}"
      run_and_log "oc get statefulsets -n ${managedNamespace}" "${MANAGED_RESOURCES_STATEFULSETS_DIR}/statefulsets.txt"
      for statefulset in $(oc get statefulsets -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        run_and_log "oc -n ${managedNamespace} get statefulset/${statefulset}" "${MANAGED_RESOURCES_STATEFULSETS_DIR}/${statefulset}.txt"
        run_and_log "oc -n ${managedNamespace} get statefulset/${statefulset} -o yaml" "${MANAGED_RESOURCES_STATEFULSETS_DIR}/${statefulset}.yaml"
        run_and_log "oc -n ${managedNamespace} get statefulset/${statefulset} -o json" "${MANAGED_RESOURCES_STATEFULSETS_DIR}/${statefulset}.json"
      done

      echo " * Getting Routs for ArgoCD Managed namespace ${managedNamespace}..."
      MANAGED_RESOURCES_ROUTES_DIR="${MANAGED_RESOURCES_DIR}/routes"
      create_directory "${MANAGED_RESOURCES_ROUTES_DIR}"
      run_and_log "oc get routes -n ${managedNamespace}" "${MANAGED_RESOURCES_ROUTES_DIR}/routes.txt"
      for route in $(oc get routes -n "${managedNamespace}" -o jsonpath='{ .items[*].metadata.name }') ; do
        run_and_log "oc -n ${managedNamespace} get route/${route}" "${MANAGED_RESOURCES_ROUTES_DIR}/${route}.txt"
        run_and_log "oc -n ${managedNamespace} get route/${route} -o yaml" "${MANAGED_RESOURCES_ROUTES_DIR}/${route}.yaml"
        run_and_log "oc -n ${managedNamespace} get route/${route} -o json" "${MANAGED_RESOURCES_ROUTES_DIR}/${route}.json"
      done
    done
  done

  echo " * Getting ArgoCD AppProjects from all Namespaces..."
  APPPROJECT_DIR="${ARGOCD_DIR}/appprojects"
  create_directory "${APPPROJECT_DIR}"
  run_and_log "oc get appProjects.argoproj.io --all-namespaces" "${ARGOCD_DIR}/appprojects.txt"
  run_and_log "oc get appProjects.argoproj.io --all-namespaces -o yaml" "${ARGOCD_DIR}/appprojects.yaml"
  run_and_log "oc get appProjects.argoproj.io --all-namespaces -o json" "${ARGOCD_DIR}/appprojects.json"

  echo " * Getting GitOps CRDs from all Namespaces..."
  CRD_DIR="${GITOPS_DIR}/crds"
  create_directory "${CRD_DIR}"
  run_and_log "oc get crds -l operators.coreos.com/openshift-gitops-operator.openshift-operators" "${CRD_DIR}/crds.txt"
  run_and_log "oc get crds -l operators.coreos.com/openshift-gitops-operator.openshift-operators -o yaml" "${CRD_DIR}/crds.yaml"
  run_and_log "oc get crds -l operators.coreos.com/openshift-gitops-operator.openshift-operators -o json" "${CRD_DIR}/crds.json"

  echo
  echo "Done! Thank you for using the GitOps must-gather tool :)"
}

main "$@"
echo
echo
if [ $ERROR_COUNTER -gt 0 ]; then
    echo "There were $ERROR_COUNTER errors"
    echo "Please check the error log file for more details: $ERROR_LOG"
else
    echo "All commands executed successfully!"
    if [ $NO_OUTPUT_COUNTER -gt 0 ]; then
        echo " * NOTE: $NO_OUTPUT_COUNTER commands did not produce any output (see: $NO_OUTPUT_LOG)"
    fi
    echo "You can find all the commands that were executed in the log file: $ALL_COMMANDS_LOG"
    exit 0
fi

echo "All other commands were successfully executed!"
if [ $NO_OUTPUT_COUNTER -gt 0 ]; then
  echo " * NOTE: $NO_OUTPUT_COUNTER commands did not produce any output (see: $NO_OUTPUT_LOG)"
  fi
echo "You can find all the commands that were executed in the log file: $ALL_COMMANDS_LOG"

