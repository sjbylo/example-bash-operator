# Example Kubernetes Operator in bash

This simple Operator is written entirely in bash and shows how to create an Operator to manage a set of pods.  It works in a similar way to the usual Kubernetes replicaset controller, it ensures that the specified number of pods are running with the specified image and command.

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
test/runall.sh 1            # run tests on one CR 
```
(Open the runall.sh file for more options) 

In a separate terminal run this command to view what's happening:

```
watch -n1 kubectl get pods
```

To stop the above commands, hit Ctrl-C. 

Optionally, view the logs of the Operator.


Stop all tests and clean up all objects:

```
test/stopall.sh
```


### Testing the Operator, step by step

To set up the Operator, cluster-admin permissions are needed.  If you want to use the Operator as a normal user, also see below. 

With cluster-admin permissions, create the Custom Resource Definition (CRD) and the role/role binding, to allow the Operator to access the Kubernetes API:

```
kubectl create -f test/crd-myapp.yaml       # create the CRD
kubectl create -f deploy/role.yaml          # The Operator needs permission to access the Operator's API group myapp.stable.example.com
kubectl create -f deploy/role_binding.yaml  
```

Now create a test CR called "myapp1":

```
kubectl create -f test/cr-myapp1.yaml	 
```

Have a look at the "myapp1" Customer Resource.  Note that "replica" is set to the required number of pods.

```
kubectl get myapp myapp1 -o yaml | grep replica
```


As a normal user (or with cluster-admin permissions), launch the Operator as a deployment:

```
kubectl create -f deploy/service_account.yaml
kubectl create -f deploy/operator.yaml
```

View the Operator output in a separate terminal:

```
kubectl logs bash-operator -f
```

### Allow a normal user to create myapp CRs (optional)

For a normal user to access the myapp custom resource, permissions (role and role binding) need to be configured.

With cluster-admin permissions, run the following:

```
kubectl create -f deploy/user_role.yaml
kubectl create -f deploy/user_role_binding.yaml    # Be sure to add your user name
```

Now, as a normal user, you can create a CR in the same way, as above.

```
kubectl create -f test/cr-myapp2.yaml	 
```

Stop the Operator:

```
kubectl delete deployment bash-operator
```

### Manual testing

The Operator can be tested with the following.

Adjust the specified replica count:

```
kubectl patch myapp myapp1 --type=json -p '[{"op": "replace", "path": "/spec/replica", "value": '3'}]'
```

Delete a pod.  The Operator will add a pod:

```
kubectl delete pod $(kubectl get pod --selector=operator=myapp1 -oname | tail -1)
```

Add a pod.  The Operator will remove a pod:

```
kubectl run myapp1-added --generator=run-pod/v1 --wait=false --image=busybox -l operator=myapp1 -- sleep 9999
```

Delete the CR itself.  The Operator clean up all pods:

```
kubectl delete myapp myapp1
```


### Run the test scripts

A test script is provided that works by randomly setting the CR replica value and by deleting and adding pods.  The Operator will ensure that the correct number of pods are always running, as defined by .spec.replica in the CR.

Start the test script in a different terminal:

```
test/test.sh myapp1
```


### Local testing on a Linux machine

On a Linux machine, ensure kubectl is installed and authenticated with a Kubernetes or OpenShift cluster.  Also ensure that "jq" is installed.

Run the Operator:

```
./operator.sh 2>err.log; sleep 1; test/cleanup.sh    # Enter Ctr-C to stop it!
```

A cleanup script can be used to remove any background processes that might get left behind after the Operator is stopped:

```
test/cleanup.sh
```


## Build the Operator

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

The following commands are useful to follow the progress during testing.  Run them in separate terminals. 

This command shows the pods that are running and the watch commands, used by the Operator:

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

You will need to create the CRD and the role with _cluster-admin_ permissions, otherwise you will see the following errors:

```
kubectl create -f test/crd-myapp.yaml
Error from server (Forbidden): error when creating "test/crd-myapp.yaml": customresourcedefinitions.apiextensions.k8s.io is forbidden: User "user0" cannot create resource "customresourcedefinitions" in API group "apiextensions.k8s.io" at the cluster scope
```
 
or

```
create -f deploy/role.yaml
Error from server (Forbidden): error when creating "deploy/role.yaml": roles.rbac.authorization.k8s.io "bash-operator" is forbidden...
```

