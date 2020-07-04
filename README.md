# Example Kubernetes Operator in bash

This simple Operator is written entirely in bash and shows how to create an Operator to manage a set of pods.  It works in a similar way to the usual Kubernetes replica-set controller, it ensures that the specified number of pods are running with the specified image and command.

The Operator is able to control multiple custom resources in a single namespace.

## Getting started

Log into Kubernetes and then create a namespace and switch to it:

```
kubectl create namespace operator-test
kubectl config set-context --current --namespace=operator-test
```

In OpenShift, just run:

```
oc new-project operator-test
```

### Test the Operator using the provided scripts

The quick way to test this is to run the following commands in separate terminals with cluster-admin permissions. This will set up the CRD and the CRs, roles and permissions, launch the Operator and run the tests. 

```
test/runall.sh 1            # run tests on one CR using image quay.io/sjbylo/bash-operator:latest
```
(See the runall.sh file for more options) 

View what's happening in a separate terminal:

```
watch -n1 kubectl get pods
```

Optionally, view the logs of the Operator.


### Testing the Operator, step by step

With cluster-admin permissions, create the Custom Resource Definition (CRD).

```
kubectl create -f test/crd-myapp.yaml  
```

As a normal user (or as cluster-admin), create a CR:

```
kubectl create -f test/cr-myapp1.yaml
```

Have a look at the "myapp1" Customer Resource.  Note that "replica" is set to the required number of pods.

```
kubectl get myapp myapp1 -o yaml | grep replica
```

### Start the Operator in Kubernetes

To allow the Operator to access the Kubernetes API, apply the manifests in the deploy directory with cluster-admin permissions:

```
kubectl create -f deploy/role.yaml
kubectl create -f deploy/role_binding.yaml
```

kubectl create -f deploy/service_account.yaml

Launch the Operator as a deployment:

```
kubectl create -f deploy/operator.yaml
```

... or launch the Operator directly as a pod:

```
kubectl run bash-operator --generator=run-pod/v1 --image=quay.io/sjbylo/bash-operator:latest
```

View the Operator output:

```
while true; do kubectl logs bash-operator -f; sleep 1; done
```

Stop the Operator:

```
kubectl delete po bash-operator
```


## Run some tests

A test script is provided that works by randomly setting the CR replica value and by deleting and adding pods.  The Operator will ensure that the correct number of pods are always running, as defined by .spec.replica in the CR.

Start the test script in a different terminal:

```
test/test.sh myapp1
```

A cleanup script can be used to remove any background processes that might get left behind after the Operator is stopped:

```
test/cleanup.sh
```

### Local testing on a Linux machine

On a Linux machine, ensure kubectl is installed and authenticated with a Kubernetes or OpenShift cluster.  Also ensure that "jq" is installed.

Run the Operator:

```
./operator.sh 2>err.log; sleep 1; test/cleanup.sh    # Enter Ctr-C to stop it!
```


## Dockerfile

A dockerfile is provided to build a container image for the Operator. 

Here is an example of building the image (use your own image repo):

```
docker build -t bash_operator . && \
docker tag  bash_operator  quay.io/sjbylo/bash-operator  && \
docker push quay.io/sjbylo/bash-operator 
```

## Work in progress

The Operator can be tested by running it directly on a Linux machine or on Kubernetes.  It has been tested on the following: RHEL 7.5, Fedora 32, Minikube, Kubernetes 1.17 and OpenShift 4.4.

Note that, for local testing purposes, the operator.sh script will not work on Mac OS (Darwin) as some of the commands in Mac OS work in different ways. 


## Miscellaneous

The following commands are useful to follow the progress during testing.  Run them in a separate terminal. 

This command shows the pods that are running and the watch commands:

```
cr=myapp1  # Set the name of your Custom Resource
watch -n1 "kubectl get po --selector=operator=$cr; ps -ef | grep 'kubectl get ' | grep -v ' watch' | grep -v grep"
```

These are the commands that are used by the Operator to set a watch on events related to the Operator (the CR and its child objects). Note that any child objects that the object manages are labeled so they they can be easily watched.

```
cr=myapp1
kubectl get myapp --watch --no-headers --ignore-not-found                        # watch the CR itself
kubectl get pod --selector=operator=$cr --watch --no-headers --ignore-not-found  # watch all controlled resources 
```

You will need to create the CRD and the role with cluster-admin permissions, otherwise you will see the following errors:

```
kubectl create -f test/crd-myapp.yaml
Error from server (Forbidden): error when creating "test/crd-myapp.yaml": customresourcedefinitions.apiextensions.k8s.io is forbidden: User "user0" cannot create resource "customresourcedefinitions" in API group "apiextensions.k8s.io" at the cluster scope
```
 
or

```
create -f deploy/role.yaml
Error from server (Forbidden): error when creating "deploy/role.yaml": roles.rbac.authorization.k8s.io "bash-operator" is forbidden...
```

