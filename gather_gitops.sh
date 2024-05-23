#!/usr/bin/env bash

set -eu -o pipefail

LOGS_DIR="/must-gather"

mkdir -p ${LOGS_DIR}

GITOPS_CURRENT_CSV=$(oc get subscription.operators.coreos.com --ignore-not-found -A -o json | jq '.items[] | select(.metadata.name=="openshift-gitops-operator") | .status.currentCSV' -r)

# Gathering cluster version all the crd related to operators.coreos.com and argoproj.io
echo "gather_gitops:$LINENO] inspecting crd, clusterversion .." | tee -a ${LOGS_DIR}/gather_gitops.log
# Getting non.existent.crd is a hack to avoid getting all available crds in the cluster in case there are no owned resources that do not contain "argoproj.io"
oc adm inspect --dest-dir=${LOGS_DIR} $(oc get crd -o name | egrep -i "argoproj.io|operators.coreos.com") $(oc get crd non.existent.crd --ignore-not-found $(oc get csv --ignore-not-found $GITOPS_CURRENT_CSV -o json | jq '.spec.customresourcedefinitions.owned[] | select(.name | contains("argoproj.io") | not) | " " + .name' -rj) -o name) clusterversion/version > /dev/null

# Gathering all namespaced custom resources across the cluster that contains "argoproj.io" related custom resources
oc get crd -o json | jq -r '.items[] | select((.spec.group | contains ("argoproj.io")) and .spec.scope=="Namespaced") | .spec.group + " " + .metadata.name + " " + .spec.names.plural' |
while read API_GROUP APIRESOURCE API_PLURAL_NAME; do 
    echo "gather_gitops:$LINENO] collecting ${APIRESOURCE} .." | tee -a ${LOGS_DIR}/gather_gitops.log
    NAMESPACES=$(oc get ${APIRESOURCE} --all-namespaces=true --ignore-not-found -o jsonpath='{range .items[*]}{@.metadata.namespace}{"\n"}{end}' | uniq)
    for NAMESPACE in ${NAMESPACES[@]}; do
        mkdir -p ${LOGS_DIR}/namespaces/${NAMESPACE}/${API_GROUP}
        oc get ${APIRESOURCE} -n ${NAMESPACE} -o=yaml >${LOGS_DIR}/namespaces/${NAMESPACE}/${API_GROUP}/${API_PLURAL_NAME}.yaml
    done
done 

# Gathering all namespaced custom resources across the cluster that are owned by gitops-operator but do not contain "argoproj.io" related customer resources
# Getting "non.existent.crd" is a hack to be sure that the output is a list of items even if it only contains zero or a single item
oc get crd --ignore-not-found non.existent.crd $(oc get csv --ignore-not-found $GITOPS_CURRENT_CSV -o json | jq '.spec.customresourcedefinitions.owned[] | select(.name | contains("argoproj.io") | not) | " " + .name' -rj)  -o json | jq -r '.items[] | select((.spec.group | contains ("argoproj.io")) and .spec.scope=="Namespaced") | .spec.group + " " + .metadata.name + " " + .spec.names.plural' |
while read API_GROUP APIRESOURCE API_PLURAL_NAME; do 
    echo "gather_gitops:$LINENO] collecting ${APIRESOURCE} .." | tee -a ${LOGS_DIR}/gather_gitops.log
    NAMESPACES=$(oc get ${APIRESOURCE} --all-namespaces=true --ignore-not-found -o jsonpath='{range .items[*]}{@.metadata.namespace}{"\n"}{end}' | uniq)
    for NAMESPACE in ${NAMESPACES[@]}; do
        mkdir -p ${LOGS_DIR}/namespaces/${NAMESPACE}/${API_GROUP}
        oc get ${APIRESOURCE} -n ${NAMESPACE} -o=yaml >${LOGS_DIR}/namespaces/${NAMESPACE}/${API_GROUP}/${API_PLURAL_NAME}.yaml
    done
done 

# Gathering all the cluster-scoped custom resources across the cluster that contains "argoproj.io"
oc get crd -o json | jq -r '.items[] | select((.spec.group | contains ("argoproj.io")) and .spec.scope=="Cluster") | .spec.group + " " + .metadata.name + " " + .spec.names.plural' |
while read API_GROUP APIRESOURCE API_PLURAL_NAME; do 
    mkdir -p ${LOGS_DIR}/cluster-scoped-resources/${API_GROUP}
    echo "gather_gitops:$LINENO] collecting ${APIRESOURCE} .." | tee -a ${LOGS_DIR}/gather_gitops.log
    oc get ${APIRESOURCE} -o=yaml >${LOGS_DIR}/cluster-scoped-resources/${API_GROUP}/${API_PLURAL_NAME}.yaml 
done 

# Gathering all cluster-scoped custom resources across the cluster that are owned by gitops-operator but do not contain "argoproj.io"
# Getting "non.existent.crd" is a hack to be sure that the output is a list of items even if it only contains zero or a single item
oc get crd --ignore-not-found non.existent.crd $(oc get csv --ignore-not-found $GITOPS_CURRENT_CSV -o json | jq '.spec.customresourcedefinitions.owned[] | select(.name | contains("argoproj.io") | not) | " " + .name' -rj)  -o json | jq -r '.items[] | select((.spec.group | contains ("argoproj.io")) and .spec.scope=="Namespaced") | .spec.group + " " + .metadata.name + " " + .spec.names.plural' |
while read API_GROUP APIRESOURCE API_PLURAL_NAME; do 
    mkdir -p ${LOGS_DIR}/cluster-scoped-resources/${API_GROUP}
    echo "gather_gitops:$LINENO] collecting ${APIRESOURCE} .." | tee -a ${LOGS_DIR}/gather_gitops.log
    oc get ${APIRESOURCE} -o=yaml >${LOGS_DIR}/cluster-scoped-resources/${API_GROUP}/${API_PLURAL_NAME}.yaml 
done 

# Inspecting namespace reported in ARGOCD_CLUSTER_CONFIG_NAMESPACES, openshift-gitops and openshift-gitops-operator, and namespaces containing ArgoCD instances
echo "gather_gitops:$LINENO] inspecting \$ARGOCD_CLUSTER_CONFIG_NAMESPACES, openshift-gitops and openshift-gitops-operator namespaces and namespaces containing ArgoCD instances .." | tee -a ${LOGS_DIR}/gather_gitops.log
oc get ns --ignore-not-found $(oc get subs -A --ignore-not-found -o json | jq '.items[] | select(.metadata.name=="openshift-gitops-operator") | .spec.config.env[]?|select(.name=="ARGOCD_CLUSTER_CONFIG_NAMESPACES")| " " + .value | sub(","; " ")' -rj) $(oc get ArgoCD,Rollout,RolloutManager -A -o json | jq '.items[] | " " + .metadata.namespace' -rj) openshift-gitops openshift-gitops-operator -o json \
| jq '.items | unique |.[] | .metadata.name' -r |
while read NAMESPACE; do
  echo "gather_gitops:$LINENO] inspecting namespace $NAMESPACE .." | tee -a ${LOGS_DIR}/gather_gitops.log
  oc adm inspect --dest-dir=${LOGS_DIR} ns/$NAMESPACE > /dev/null
  echo "gather_gitops:$LINENO] inspecting csv,sub,ip for namespace $NAMESPACE .." | tee -a ${LOGS_DIR}/gather_gitops.log
  oc adm inspect --dest-dir=${LOGS_DIR} $(oc get --ignore-not-found clusterserviceversions.operators.coreos.com,installplans.operators.coreos.com,subscriptions.operators.coreos.com -o name -n $NAMESPACE) -n $NAMESPACE &> /dev/null \
  || echo "gather_gitops:$LINENO] no csv,sub,ip found in namespace $NAMESPACE .." | tee -a ${LOGS_DIR}/gather_gitops.log
done

# Inspecting namespace managed by ArgoCD
echo "gather_gitops:$LINENO] inspecting namespaces managed by ArgoCD .." | tee -a ${LOGS_DIR}/gather_gitops.log
oc get ns -o json | jq '.items[] | select(.metadata.labels | keys[] | contains("argocd.argoproj.io/managed-by")) | .metadata.name' -r |
while read NAMESPACE; do
  echo "gather_gitops:$LINENO] inspecting namespace $NAMESPACE .." | tee -a ${LOGS_DIR}/gather_gitops.log
  oc adm inspect --dest-dir=${LOGS_DIR} ns/$NAMESPACE > /dev/null
done