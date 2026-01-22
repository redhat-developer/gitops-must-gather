# GitOps Operator Must-Gather

`GitOps must-gather` is a tool to gather information about the gitop-operator. It is built on top of [OpenShift must-gather](https://github.com/openshift/must-gather).

## Usage

```sh
oc adm must-gather --image=registry.redhat.io/openshift-gitops-1/gitops-must-gather-rhel-8:$GITOPS_VERSION
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

To get data about other parts of the cluster (not specific to [gitops-operator](https://github.com/redhat-developer/gitops-operator/)), run `oc adm must-gather` (without passing a custom image).
Run `oc adm must-gather -h` to see more options.

## Development

Make sure you run `make lint` before pushing new changes.
This requires `shellcheck` to be installed in your machine.

For more information about `building` and `pushing` the image, see `make help`.

### Image publishing

CD images are pushed to the following destinations, from where they can be used for testing:

- HEAD of the `main` branch: quay.io/redhat-user-workloads/rh-openshift-gitops-tenant/gitops-must-gather:latest
- PRs: quay.io/redhat-user-workloads/rh-openshift-gitops-tenant/gitops-must-gather:on-pr-<GIT_COMMIT_SHA>
- `main` branch: quay.io/redhat-user-workloads/rh-openshift-gitops-tenant/gitops-must-gather:<GIT_COMMIT_SHA>

Custom image can be pushed, too:

```shell
# You may need to create the repository on quay.io manually to make sure it is public
make REGISTRY_USERNAME=my-non-production-org CONTAINER_IMAGE_TAG=latest push
```
It is recomanded to use `latest` tag for development, because it does not get cached on OpenShift nodes - other tags might.

## Testing

Create the OpenShift cluster, log in and install the Red Hat GitOps Operator.

For the development version, use:
```shell
git clone https://github.com/redhat-developer/gitops-operator/
cd gitops-operator
make clean install 
```

### Compare gathered data between 2 gitops-must-gather images

```shell
# Note some differences are expected, like a few lines at the end of rapidly populated logs, etc.
./test/compare.sh registry.redhat.io/openshift-gitops-1/must-gather-rhel8:"$SOME_OLD_VERSION" quay.io/my-non-production-org/gitops-must-gather:latest
```

### Verify the structure of the must-gather output

```shell
# After logging in to a cluster
git clone https://github.com/redhat-developer/gitops-operator/
cd gitops-operator
env E2E_MUST_GATHER_IMAGE=<TESTED_IMAGE_HERE> LOCAL_RUN=true \
    ./bin/ginkgo -v -focus "validate_running_must_gather" -r ./test/openshift/e2e/ginkgo/parallel/
```
