# GitOps Operator Must-Gather
=================

`GitOps must-gather` is a tool to gather information about the gitop-operator. It is built on top of [OpenShift must-gather](https://github.com/openshift/must-gather).

### Usage
```sh
oc adm must-gather --image=quay.io/redhat-developer/gitops-must-gather:latest
```

The command above will create a local directory with a dump of the OpenShift GitOps state. Note that this command will only get data related to the GitOps Operator in your OpenShift cluster.

You will get a dump of:
- Information for the subscription of the gitops-operator
- The GitOps Operator namespace (and its children objects)
- All namespaces where ArgoCD objects exist in, plus all objects in those namespaces, such as ArgoCD, Applications, ApplicationSets, and AppProjects, and configmaps
  - No secrets will be collected
- A list of list of the namespaces that are managed by gitops-operator identified namespaces and resources from those namespaces. 
- All GitOps CRD's objects and definitions
- Operator logs
- Logs of Argo CD
- Warning and error-level Events

In order to get data about other parts of the cluster (not specific to gitops-operator) you should run just `oc adm must-gather` (without passing a custom image). Run `oc adm must-gather -h` to see more options.

An example of the GitOps must-gather output would be something like the following, where there are two argocd instances in namespaces `openshift-gitops` and `foo` and an additional namespace called `foo-managed` which is managed by namespace `foo`:
```
cluster-gitops
        └── gitops
            ├── appprojects.yaml
            ├── crds.yaml
            ├── namespace_openshift-gitops_resources
            │   ├── application_controller_logs.txt
            │   ├── applications
            │   ├── applicationsets
            │   ├── argocd.yaml
            │   ├── deployments
            │   │   ├── cluster.yaml
            │   │   └── kam.yaml
            │   ├── dex-server_logs.txt
            │   ├── error-events.txt
            │   ├── pods
            │   │   ├── cluster-5db4b95547-rdz2m.yaml
            │   │   └── kam-fff7f474f-d27c8.yaml
            │   ├── redis_logs.txt
            │   ├── replicasets
            │   │   ├── cluster-5db4b95547.yaml
            │   │   └── kam-fff7f474f.yaml
            │   ├── repo-server_logs.txt
            │   ├── routes
            │   │   └── kam.yaml
            │   ├── server_logs.txt
            │   ├── services
            │   │   ├── cluster.yaml
            │   │   └── kam.yaml
            │   ├── statefulsets
            │   └── warning-events.txt
            ├── namespace_foo_resources
            │   ├── application_controller_logs.txt
            │   ├── applications
            │   │   └── guestbook.yaml
            │   ├── applicationsets
            │   │   └── guestbook.yaml
            │   ├── argocd.yaml
            │   ├── deployments
            │   ├── dex-server_logs.txt
            │   ├── error-events.txt
            │   ├── managedNamespace_foo-managed
            │   │   ├── deployments
            │   │   ├── pods
            │   │   ├── replicasets
            │   │   ├── routes
            │   │   ├── services
            │   │   └── statefulsets
            │   ├── pods
            │   ├── redis_logs.txt
            │   ├── replicasets
            │   ├── repo-server_logs.txt
            │   ├── routes
            │   ├── server_logs.txt
            │   ├── services
            │   ├── statefulsets
            │   └── warning-events.txt
            ├── oc-version.txt
            └── subscription.yaml
```