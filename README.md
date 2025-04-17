# GitOps Operator Must-Gather

`GitOps must-gather` is a tool to gather information about the gitop-operator. It is built on top of [OpenShift must-gather](https://github.com/openshift/must-gather).

## Usage

```sh
oc adm must-gather --image=registry.redhat.io/openshift-gitops-1/gitops-must-gather-rhel-8:v1.9.0
```

The command above will create a local directory with a dump of the OpenShift GitOps state. Note that this command will only get data related to the GitOps Operator in your OpenShift cluster.

You will get a dump of:

- Information for the subscription of the gitops-operator
- The GitOps Operator namespace (and its children objects)
- All namespaces where ArgoCD objects exist in, plus all objects in those namespaces, such as ArgoCD, Applications, ApplicationSets, and AppProjects, and configmaps
  - No secrets will be collected
- A list of the namespaces that are managed by gitops-operator identified namespaces and resources from those namespaces.
- All GitOps CRD's objects and definitions
- Operator logs
- Logs of Argo CD
- Warning and error-level Events

In addition to that, we will get a summary of:

- All executed commands: `must-gather-script-commands.txt`
- Errors: `must-gather-script-errors.txt`
- Commands that produced no output: `must-gather-script-no-output.txt`

All the output of the commands is stored into 3 different formats:

- `*.txt` that represents the normal view without any structure.
- `*.yaml` that is the YAML output of the command.
- `*.json` that is the JSON output of the command.

In order to get data about other parts of the cluster (not specific to gitops-operator) you should run just `oc adm must-gather` (without passing a custom image). Run `oc adm must-gather -h` to see more options.

An example of the GitOps must-gather output would be something like the following, where there are two argocd instances in namespaces `openshift-gitops` and `foo` and an additional namespace called `foo-managed` which is managed by namespace `foo`:

```shell
cluster-gitops
    └── gitops
        ├── clusterversion.txt
        ├── crds
        │  ├── crds.json/.txt./.yaml
        ├── managedNamespace_foo-managed
        │  └── resources
        │      ├── deployments
        │      ├── pods
        │      ├── replicasets
        │      ├── routes
        │      ├── services
        │      └── statefulsets
        ├── namespace_foo_resources
        │  ├── argocd
        │  │  ├── applications
        │  │  │  ├── applications.json/.txt./.yaml
        │  │  │  └── guestbook.yaml
        │  │  ├── applicationsets
        │  │  │  ├── applicationsets.txt
        │  │  │  ├── guestbook.json
        │  │  │  ├── guestbook.txt
        │  │  │  └── guestbook.yaml
        │  │  ├── argocd.json
        │  │  ├── argocd.txt
        │  │  ├── argocd.yaml
        │  │  ├── logs
        │  │  │  └── server-logs.txt
        │  │  ├── managed-namespaces.txt
        │  │  └── sourceNamespaces.txt
        │  ├── deployments
        │  │  ├── argocd-dex-server.json/.txt./.yaml
        │  │  ├── argocd-redis.json/.txt./.yaml
        │  │  ├── argocd-repo-server.json/.txt./.yaml
        │  │  ├── argocd-server.json/.txt./.yaml
        │  │  └── deployments.txt
        │  ├── events
        │  │  ├── all-events.txt
        │  │  └── warning-events.txt
        │  ├── pods
        │  │  ├── argocd-application-controller-0.json/.txt./.yaml
        │  │  ├── argocd-dex-server-69f99bdd45-g84b9.json/.txt./.yaml
        │  │  ├── argocd-dex-server-6d4f7d9d48-rkk9d.json/.txt./.yaml
        │  │  ├── argocd-redis-78d4849f68-pxxbp.json/.txt./.yaml
        │  │  ├── argocd-repo-server-6cfc8bbd5f-w4bsg.json/.txt./.yaml
        │  │  ├── argocd-server-5dc69475bf-98m6s.json/.txt./.yaml
        │  │  └── pods.txt
        │  ├── replicaSets
        │  │  ├── argocd-dex-server-69f99bdd45.json/.txt./.yaml
        │  │  ├── argocd-dex-server-6d4f7d9d48.json/.txt./.yaml
        │  │  ├── argocd-redis-78d4849f68.json/.txt./.yaml
        │  │  ├── argocd-repo-server-6cfc8bbd5f.json/.txt./.yaml
        │  │  ├── argocd-server-5dc69475bf.json/.txt./.yaml
        │  │  └── replicaSets.txt
        │  ├── routes
        │  │  ├── argocd-server.json/.txt./.yaml
        │  │  └── routes.txt
        │  ├── services
        │  │  ├── argocd-dex-server.json/.txt./.yaml
        │  │  ├── argocd-metrics.json/.txt./.yaml
        │  │  ├── argocd-redis.json/.txt./.yaml
        │  │  ├── argocd-repo-server.json/.txt./.yaml
        │  │  ├── argocd-server.json/.txt./.yaml
        │  │  ├── argocd-server-metrics.json/.txt./.yaml
        │  │  └── services.txt
        │  └── statefulsets
        │      ├── argocd-application-controller.json/.txt./.yaml
        │      └── statefulsets.txt
        ├── namespace_openshift-gitops_resources
        │  ├── argocd
        │  │  ├── applications
        │  │  ├── applicationsets
        │  │  ├── appprojects
        │  │  ├── appprojects.json/.txt./.yaml
        │  │  ├── argocd.txt
        │  │  ├── logs
        │  │  │  ├── application-controller-logs.txt
        │  │  │  ├── dex-server-logs.txt
        │  │  │  ├── redis-logs.txt
        │  │  │  ├── repo-server-logs.txt
        │  │  │  └── server-logs.txt
        │  │  ├── openshift-gitops.json
        │  │  ├── openshift-gitops.txt
        │  │  ├── openshift-gitops.yaml
        │  │  └── sourceNamespaces.txt
        │  ├── deployments
        │  │  ├── cluster.json/.txt./.yaml
        │  │  ├── deployments.txt
        │  │  ├── kam.json
        │  │  ├── kam.txt
        │  │  ├── kam.yaml
        │  │  ├── openshift-gitops-applicationset-controller.json/.txt./.yaml
        │  │  ├── openshift-gitops-dex-server.json/.txt./.yaml
        │  │  ├── openshift-gitops-redis.json/.txt./.yaml
        │  │  ├── openshift-gitops-repo-server.json/.txt./.yaml
        │  │  ├── openshift-gitops-server.json/.txt./.yaml
        │  ├── events
        │  ├── pods
        │  │  ├── cluster-5db4b95547-mks98.json/.txt./.yaml
        │  │  ├── kam-fff7f474f-t875v.json/.txt./.yaml
        │  │  ├── openshift-gitops-application-controller-0.json/.txt./.yaml
        │  │  ├── openshift-gitops-applicationset-controller-5dbdfcc689-6x4vf.json/.txt./.yaml
        │  │  ├── openshift-gitops-dex-server-5bf6f4f684-ghtqf.json/.txt./.yaml
        │  │  ├── openshift-gitops-redis-664cdd4757-f9jcc.json/.txt./.yaml
        │  │  ├── openshift-gitops-repo-server-6795d6d8cd-x7hzc.json/.txt./.yaml
        │  │  ├── openshift-gitops-server-6cc58f9cc8-fx8g7.json/.txt./.yaml
        │  │  └── pods.txt
        │  ├── replicaSets
        │  │  ├── cluster-5db4b95547.json/.txt./.yaml
        │  │  ├── kam-fff7f474f.json/.txt./.yaml
        │  │  ├── openshift-gitops-applicationset-controller-5dbdfcc689.json/.txt./.yaml
        │  │  ├── openshift-gitops-dex-server-5bf6f4f684.json/.txt./.yaml
        │  │  ├── openshift-gitops-dex-server-684c85d5d7.json/.txt./.yaml
        │  │  ├── openshift-gitops-redis-664cdd4757.json/.txt./.yaml
        │  │  ├── openshift-gitops-repo-server-6795d6d8cd.json/.txt./.yaml
        │  │  ├── openshift-gitops-server-6cc58f9cc8.json/.txt./.yaml
        │  │  └── replicaSets.txt
        │  ├── routes
        │  │  ├── kam.json/.txt./.yaml
        │  │  ├── openshift-gitops-server.json/.txt./.yaml
        │  │  └── routes.txt
        │  ├── services
        │  │  ├── cluster.json/.txt./.yaml
        │  │  ├── kam.json/.txt./.yaml
        │  │  ├── openshift-gitops-applicationset-controller.json/.txt./.yaml
        │  │  ├── openshift-gitops-dex-server.json/.txt./.yaml
        │  │  ├── openshift-gitops-metrics.json/.txt./.yaml
        │  │  ├── openshift-gitops-redis.json/.txt./.yaml
        │  │  ├── openshift-gitops-repo-server.json/.txt./.yaml
        │  │  ├── openshift-gitops-server.json/.txt./.yaml
        │  │  ├── openshift-gitops-server-metrics.json/.txt./.yaml
        │  │  └── services.txt
        │  └── statefulsets
        │      ├── openshift-gitops-application-controller.json/.txt./.yaml
        │      └── statefulsets.txt
        ├── oc-version.txt
        ├── subscription.json/.txt./.yaml
        ├── must-gather-script-commands.txt
        ├── must-gather-script-no-output.txt
        └── must-gather-script-errors.txt
```
Note: most of the resource outputs are given in 3 file types: `.json`, `.yaml`, and `.txt`, however those files are combined in this tree for clarity and conciseness. 

## Testing

You can run the script locally from your workstation.
To do that you need an OpenShift cluster and you will have to install the Red Hat GitOps Operator.
Then you can run the script like this:

```shell
chmod +x ./gather_gitops.sh
./gather_gitops.sh --base-collection-path .
```

Last but not least, please make sure you run `make lint` before pushing new changes.
This requires `shellcheck` to be installed in your machine.

For more information about `building` and `pushing` the image, see `make help`.
