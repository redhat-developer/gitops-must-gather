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

get_namespaces() {
  local namespaces
  local default="openshift-gitops"
  local clusterScopedInstances
  clusterScopedInstances=$(oc get subs openshift-gitops-operator -n openshift-operators -o json | jq '.spec.config.env[]?|select(.name=="ARGOCD_CLUSTER_CONFIG_NAMESPACES").value' | tr -d '",')
  disableDefaultArgoCDInstanceValue=$(oc get subs openshift-gitops-operator -n openshift-operators -o json | jq '.spec.config.env[]?|select(.name=="DISABLE_DEFAULT_ARGOCD_INSTANCE").value')
  if [[ "$(oc get subs openshift-gitops-operator -n openshift-operators -o jsonpath='{.spec.config.env}')" == "" ]]; then
    namespaces="${default}"
  elif [[ "${clusterScopedInstances}" != "" ]]; then
    if [[ "${disableDefaultArgoCDInstanceValue}" == "true" ]]; then
      namespaces+="${clusterScopedInstances}"
    else
      namespaces="${clusterScopedInstances} ${default}"
    fi
  else 
    mkdir -p $1
    echo "Error: get_namespaces- No gitops instances found, please check your cluster configuration." > $1/must-gather-script-errors.yaml 2>&1
  fi

  local argocdInstances
  argocdInstances=$(oc get ArgoCD --all-namespaces -o jsonpath='{.items[*].metadata.namespace}')

  local total
  total="${namespaces} ${argocdInstances}"
  echo "${total}"
  
  NAMESPACES=$(echo "${total}" | tr ' ' '\n' | sort -u | tr '\n' ' ')
  export NAMESPACES
}

# gets pods; takes namespace and directory as argument
get_pods() {
  echo " * Getting pods in $1..."
  run_and_log "oc get pods -n $1" "$2/pods.txt"
  for pod in $(oc get pods -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get pod/${pod}" "$2/${pod}.txt"
    run_and_log "oc -n $1 get pod/${pod} -o yaml" "$2/${pod}.yaml"
    run_and_log "oc -n $1 get pod/${pod} -o json" "$2/${pod}.json"
    run_and_log "oc -n $1 logs pod/${pod}" "$2/${pod}-logs.txt"
  done
}

# gets deployments; takes namespace and directory as argument
get_deployments(){
  echo " * Getting deployments in $1..."
  run_and_log "oc get deployments -n $1" "$2/deployments.txt"
  for deployment in $(oc get deployments -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get deployment/${deployment}" "$2/${deployment}.txt"
    run_and_log "oc -n $1 get deployment/${deployment} -o yaml" "$2/${deployment}.yaml"
    run_and_log "oc -n $1 get deployment/${deployment} -o json" "$2/${deployment}.json"
  done
}

# gets services; takes namespace and directory as argument
get_services(){
  echo " * Getting services in $1..."
  run_and_log "oc get services -n $1" "$2/services.txt"
  for service in $(oc get services -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get service/${service}" "$2/${service}.txt"
    run_and_log "oc -n $1 get service/${service} -o yaml" "$2/${service}.yaml"
    run_and_log "oc -n $1 get service/${service} -o json" "$2/${service}.json"
  done
}

# gets replicasets; takes namespace and directory as argument
get_replicaSets(){
  echo " * Getting replicaSets in $1..."
  run_and_log "oc get replicasets -n $1" "$2/replicaSets.txt"
  for replicaset in $(oc get replicasets -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get replicaset/${replicaset}" "$2/${replicaset}.txt"
    run_and_log "oc -n $1 get replicaset/${replicaset} -o yaml" "$2/${replicaset}.yaml"
    run_and_log "oc -n $1 get replicaset/${replicaset} -o json" "$2/${replicaset}.json"
  done
}

# gets statefulsets; takes namespace and directory as argument
get_statefulSets(){
  echo " * Getting statefulsets in $1..."
  run_and_log "oc get statefulsets -n $1" "$2/statefulsets.txt"
  for statefulset in $(oc get statefulsets -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get statefulset/${statefulset}" "$2/${statefulset}.txt"
    run_and_log "oc -n $1 get statefulset/${statefulset} -o yaml" "$2/${statefulset}.yaml"
    run_and_log "oc -n $1 get statefulset/${statefulset} -o json" "$2/${statefulset}.json"
  done
}

# gets routes; takes namespace and directory as argument
get_routes(){
  echo " * Getting routes in $1..."
  run_and_log "oc get routes -n $1" "$2/routes.txt"
  for route in $(oc get routes -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get route/${route}" "$2/${route}.txt"
    run_and_log "oc -n $1 get route/${route} -o yaml" "$2/${route}.yaml"
    run_and_log "oc -n $1 get route/${route} -o json" "$2/${route}.json"
  done
}

# gets argocd instances; takes namespace and directory as argument
get_argocds(){
  echo " * Getting ArgoCD in $1..."
  run_and_log "oc get argocd -n $1" "$2/argocd.txt"
  for argocd in $(oc get argocd -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get argocd/${argocd}" "$2/${argocd}.txt"
    run_and_log "oc -n $1 get argocd/${argocd} -o yaml" "$2/${argocd}.yaml"
    run_and_log "oc -n $1 get argocd/${argocd} -o json" "$2/${argocd}.json"
  done
}

# gets applications; takes namespace and directory as arguments
get_applications(){
  echo " * Getting ArgoCD Applications in $1..."
  run_and_log "oc get applications.argoproj.io -n $1" "$2/applications.txt"
  for application in $(oc get applications.argoproj.io -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get applications.argoproj.io/${application}" "$2/${application}.txt"
    run_and_log "oc -n $1 get applications.argoproj.io/${application} -o yaml" "$2/${application}.yaml"
    run_and_log "oc -n $1 get applications.argoproj.io/${application} -o json" "$2/${application}.json"
  done
}

# gets applicationSets; takes namespace and directory as arguments
get_applicationSets(){
  echo " * Getting ArgoCD ApplicationSets in $1..."
  run_and_log "oc get applicationsets.argoproj.io -n $1" "$2/applicationsets.txt"
  for applicationset in $(oc get applicationsets.argoproj.io -n "$1" -o jsonpath='{ .items[*].metadata.name }') ; do
    run_and_log "oc -n $1 get applicationsets.argoproj.io/${applicationset}" "$2/${applicationset}.txt"
    run_and_log "oc -n $1 get applicationsets.argoproj.io/${applicationset} -o yaml" "$2/${applicationset}.yaml"
    run_and_log "oc -n $1 get applicationsets.argoproj.io/${applicationset} -o json" "$2/${applicationset}.json"
  done
}

# gets Events; takes namespace and directory as parameter
get_events(){
  echo " * Getting warning events in $1..."
  run_and_log "oc get events -n $1 --field-selector type=Warning" "$2/warning-events.txt"
  echo " * Getting error events in $1..."
  run_and_log "oc get events -n $1 --field-selector type=Error" "$2/error-events.txt"
  echo " * Getting all events in $1..."
  run_and_log "oc get events -n $1" "$2/all-events.txt"
}

function main_function() {

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
  get_namespaces "$GITOPS_DIR"

  echo " * Getting OpenShift Cluster Version..."
  run_and_log "oc version" "$GITOPS_DIR/oc-version.txt"

  # requirement for custom must-gathers, see https://github.com/openshift/enhancements/blob/a5841f75dbc9afbab22e5baa8d2f1ff2f43e2df7/enhancements/oc/must-gather.md?plain=1#L88
  echo " * Getting OpenShift GitOps Version..."
  csv_name="$(oc -n openshift-gitops get csv -o name | grep 'openshift-gitops-operator')"
  oc -n openshift-gitops get "${csv_name}" -o jsonpath='{.spec.displayName}{"\n"}{.spec.version}' > "$GITOPS_DIR/version.txt"

  echo " * Getting GitOps Operator Subscription..."
  run_and_log "oc get subs openshift-gitops-operator -n openshift-operators -o yaml" "$GITOPS_DIR/subscription.yaml"
  run_and_log "oc get subs openshift-gitops-operator -n openshift-operators -o json" "$GITOPS_DIR/subscription.json"
  run_and_log "oc get subs openshift-gitops-operator -n openshift-operators" "$GITOPS_DIR/subscription.txt"

  for namespace in ${NAMESPACES}; do
    RESOURCES_DIR="${GITOPS_DIR}/namespace_${namespace}_resources"
    create_directory "${RESOURCES_DIR}"

    POD_DIR="${RESOURCES_DIR}/pods"
    create_directory "${POD_DIR}"
    get_pods "${namespace}" "${POD_DIR}"
 
    DEPLOYMENT_DIR="${RESOURCES_DIR}/deployments"
    create_directory "${DEPLOYMENT_DIR}"
    get_deployments "${namespace}" "${DEPLOYMENT_DIR}"

    SERVICE_DIR="${RESOURCES_DIR}/services"
    create_directory "${SERVICE_DIR}"
    get_services "${namespace}" "${SERVICE_DIR}"

    REPLICASET_DIR="${RESOURCES_DIR}/replicaSets"
    create_directory "${REPLICASET_DIR}"
    get_replicaSets "${namespace}" "${REPLICASET_DIR}"

    STATEFULSET_DIR="${RESOURCES_DIR}/statefulsets"
    create_directory "${STATEFULSET_DIR}"
    get_statefulSets "${namespace}" "${STATEFULSET_DIR}"

    ROUTE_DIR="${RESOURCES_DIR}/routes"
    create_directory "${ROUTE_DIR}"
    get_routes "${namespace}" "${ROUTE_DIR}"

    ARGOCD_DIR="${RESOURCES_DIR}/argocd"
    create_directory "${ARGOCD_DIR}"
    get_argocds "${namespace}" "${ARGOCD_DIR}"

    APPLICATION_DIR="${ARGOCD_DIR}/applications"
    create_directory "${APPLICATION_DIR}"
    get_applications "${namespace}" "${APPLICATION_DIR}"

    echo " * Getting ArgoCD Source Namespaces in ${namespace}..."
    local sourceNamespaces
    run_and_log "oc get argocd -n ${namespace} -o jsonpath='{.items[*].spec.sourceNamespaces[*]}'" "${ARGOCD_DIR}/sourceNamespaces.txt"
    sourceNamespaces=$(oc get argocd -n "${namespace}" -o jsonpath='{.items[*].spec.sourceNamespaces[*]}' )
    if [[ "${sourceNamespaces}" != "" ]] ; then
      for sourceNamespace in ${sourceNamespaces} ; do 
        SOURCED_DIR="${ARGOCD_DIR}/namespace_${sourceNamespace}_resources/applications"
        get_applications "${sourceNamespace}" "${SOURCED_DIR}"
      done
    fi

    APPLICATIONSETS_DIR="${ARGOCD_DIR}/applicationsets"
    create_directory "${APPLICATIONSETS_DIR}"
    get_applicationSets "${namespace}" "${APPLICATIONSETS_DIR}"

    EVENTS_DIR="${RESOURCES_DIR}/events" 
    create_directory "${EVENTS_DIR}"
    get_events "${namespace}" "${EVENTS_DIR}"

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
      MANAGED_RESOURCES_DIR="${RESOURCES_DIR}/managedNamespace_${managedNamespace}"
      create_directory "${MANAGED_RESOURCES_DIR}"

      MANAGED_RESOURCES_PODS_DIR="${MANAGED_RESOURCES_DIR}/pods"
      create_directory "${MANAGED_RESOURCES_PODS_DIR}"
      get_pods "${managedNamespace}" "${MANAGED_RESOURCES_PODS_DIR}"

      MANAGED_RESOURCES_DEPLOYMENTS_DIR="${MANAGED_RESOURCES_DIR}/deployments"
      create_directory "${MANAGED_RESOURCES_DEPLOYMENTS_DIR}"
      get_deployments "${managedNamespace}" "${MANAGED_RESOURCES_DEPLOYMENTS_DIR}"

      MANAGED_RESOURCES_SERVICES_DIR="${MANAGED_RESOURCES_DIR}/services"
      create_directory "${MANAGED_RESOURCES_SERVICES_DIR}"
      get_services "${managedNamespace}" "${MANAGED_RESOURCES_SERVICES_DIR}"

      MANAGED_RESOURCES_ROUTES_DIR="${MANAGED_RESOURCES_DIR}/routes"
      create_directory "${MANAGED_RESOURCES_ROUTES_DIR}"
      get_routes "${managedNamespace}" "${MANAGED_RESOURCES_ROUTES_DIR}"

      MANAGED_RESOURCES_REPLICASETS_DIR="${MANAGED_RESOURCES_DIR}/replicasets"
      create_directory "${MANAGED_RESOURCES_REPLICASETS_DIR}"
      get_replicaSets "${managedNamespace}" "${MANAGED_RESOURCES_REPLICASETS_DIR}"

      MANAGED_RESOURCES_STATEFULSETS_DIR="${MANAGED_RESOURCES_DIR}/statefulsets"
      create_directory "${MANAGED_RESOURCES_STATEFULSETS_DIR}"
      get_statefulSets "${managedNamespace}" "${MANAGED_RESOURCES_STATEFULSETS_DIR}"
    done
  done

  echo " * Getting ArgoCD AppProjects from all Namespaces..."
  APPPROJECT_DIR="${ARGOCD_DIR}/appprojects"
  create_directory "${APPPROJECT_DIR}"
  run_and_log "oc get appProjects.argoproj.io --all-namespaces" "${APPPROJECT_DIR}/appprojects.txt"
  run_and_log "oc get appProjects.argoproj.io --all-namespaces -o yaml" "${APPPROJECT_DIR}/appprojects.yaml"
  run_and_log "oc get appProjects.argoproj.io --all-namespaces -o json" "${APPPROJECT_DIR}/appprojects.json"

  echo " * Getting GitOps CRDs from all Namespaces..."
  CRD_DIR="${GITOPS_DIR}/crds"
  create_directory "${CRD_DIR}"
  run_and_log "oc get crds -l operators.coreos.com/openshift-gitops-operator.openshift-operators" "${CRD_DIR}/crds.txt"
  run_and_log "oc get crds -l operators.coreos.com/openshift-gitops-operator.openshift-operators -o yaml" "${CRD_DIR}/crds.yaml"
  run_and_log "oc get crds -l operators.coreos.com/openshift-gitops-operator.openshift-operators -o json" "${CRD_DIR}/crds.json"

  echo
  echo "Done! Thank you for using the GitOps must-gather tool :)"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # The script is being executed as a script
  # Call the desired function here
  main_function
else
  # The script is being sourced as a library
  # Define the main function here
  function main() {
    # Call the supporting functions here
    create_directory
    run_and_log
    exit_if_binary_not_installed
    exit_if_not_openshift
    get_applications
    get_applicationSets
    get_argocds
    get_deployments
    get_events
    get_namespaces
    get_pods
    get_replicaSets
    get_routes
    get_services
    get_statefulSets
  }
  # Call the main function here if the script is being executed as a script
  main "$@"
fi

# main "$@"
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

