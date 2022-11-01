# Example Kubernetes Operator in bash

This project was created for fun and learning purposes only!

This simple [Operator](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/) is written entirely in bash and shows how to create an Operator to control a set of pods.  It works in a similar way to the usual Kubernetes replicaset controller, it ensures that the specified number of pods are running with the specified image and command.

The Operator is able to control multiple custom resources in a single namespace. 

## Getting started

You'll need access to a Kubernetes cluster and the kubectl tool.  Here is how to [install kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/). If you don't have access to a cluster, you could try installing [Minikube](https://minikube.sigs.k8s.io/docs/) on your workstation.  Or open up Kubernetes in your browser at [Killercoda Playground](https://killercoda.com/kubernetes/scenario/a-playground).

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

First, clone this repo!

```
git clone https://github.com/sjbylo/example-bash-operator.git
cd example-bash-operator
```

The quick way to test this is to run the following commands in separate terminals with cluster-admin permissions. This will set up the Custom Resource Definition (CRD) and the Custom Resources (CR), roles and permissions, launch the Operator and run the tests.  Note that the first time this is run, the test images (busybox and whalesay) need to be pulled, so the tests might timeout and fail.  Just try again if this happens.  

```
test/startall.sh 1            # run tests on one CR 
```
(Open the startall.sh file for more options) 

In separate terminals run the following commands to view what's happening:

```
watch -n1 kubectl get pods    # View the controlled pods
```

To view what the Operator is doing, run:

```
test/logs.sh  
LOGLEVEL=1
MyApp Operator process ID: 6
INTERVAL_MS=4000
Starting watch for custom resource: myapp/myapp1
Starting reconcile function for custom resource: myapp/myapp1
myapp1 0/1 running. Replica mismatch, adjusting pod count by 1
myapp1 1/1 running. Nothing to do
Terminating processes:
Exiting controller for myapp/myapp1 ...
Starting watch for custom resource: myapp/myapp1
Starting reconcile function for custom resource: myapp/myapp1
myapp1 0/2 running. Replica mismatch, adjusting pod count by 2
myapp1 2/2 running. Nothing to do
myapp1 1/2 running. Replica mismatch, adjusting pod count by 1
myapp1 2/2 running. Nothing to do
myapp1 2/2 running. Nothing to do
myapp1 2/2 running. Image or command change, replacing all pods ...
myapp1 2/2 running. Nothing to do
myapp1 4/2 running. Replica mismatch, adjusting pod count by -2
...
```


To stop the above commands, hit Ctrl-C. 


Stop all tests and clean up all objects:

```
test/stopall.sh
```


### Testing the Operator, step by step

Be sure to run the above "stopall" script before you begin here.

To set up the Operator, cluster-admin permissions are needed.  If you want to use the Operator as a normal user, also see below. 

With cluster-admin permissions, create the Custom Resource Definition (CRD) and the role/role binding, to allow the Operator to access the Kubernetes API:

```
kubectl create -f deploy/crd-myapp.yaml      # create the CRD
kubectl create -f deploy/role.yaml           # The Operator needs permission to access the Operator's API group myapp.stable.example.com
kubectl create -f deploy/role_binding.yaml  
```

Now create a test CR called "myapp1":

```
kubectl create -f deploy/cr-myapp1.yaml	 
```

Have a look at the "myapp1" Custom Resource.  Note that "replica" is set to the required number of pods.

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
test/logs.sh    # View Operator output
```

### Allow a normal user to create myapp CRs (optional)

For a normal user to access the myapp custom resource, permissions (role and role binding) need to be configured.

With cluster-admin permissions, run the following:

```
kubectl create -f deploy/user_role.yaml
kubectl create -f deploy/user_role_binding.yaml  
```

Now, as a normal user, you can create a CR in the same way, as above.

```
kubectl create -f deploy/cr-myapp2.yaml	--as=some-normal-user
```

### Manual testing

The Operator can be tested with the following.

Adjust the specified replica count:

```
kubectl patch myapp myapp1 --type=json -p '[{"op": "replace", "path": "/spec/replica", "value": '3'}]'
```

Delete a pod.  The Operator will add a pod:

```
kubectl delete $(kubectl get pod --selector=myapp=myapp1 -oname | tail -1) --now
```

Add a pod.  The Operator will remove a pod:

```
kubectl run myapp1-added --wait=false --image=busybox -l myapp=myapp1 -- sleep 9999
```

Delete the CR itself.  The Operator will clean up all controlled pods:

```
kubectl delete myapp myapp1
```


### Run the test script on its own

A test script is provided that works by randomly setting the CR's replica value, deleting and adding pods, deleting and removing CRs and switching the desired image.  The Operator will ensure that the correct number of pods are always running, as defined by .spec.replica in each CR.  The script can be run multiple times in parallel to simulate multiple CRs.

Start one or more test scripts in a different terminal:

```
test/test.sh myapp1
# or
( test/test.sh myapp1 & test/test.sh myapp2 )
```



### Local testing on a Linux machine

The Operator can be tested by running it directly on a Linux machine.  It has been tested on the following: MacOS (with brew), RHEL 7.5, Fedora 32, Minikube, Kubernetes 1.17 and OpenShift 4.4.

Note that, for local testing purposes, the operator.sh script will also work on Mac OS (Darwin) as long as bash is v4 or above and gtr and gdate are installed with 'brew install coreutils'.  The Operator requires bash version 4 or above because it makes use of associative arrays.

On a Linux machine, ensure kubectl is installed and authenticated with a Kubernetes or OpenShift cluster.  Also ensure that "jq" is installed.

Run the Operator:

```
./operator.sh 2>err.log    # Enter Ctr-C to stop it!
```

Test the Operator using the test script:

```
test/test.sh myapp1
```

Just in case, a cleanup script can be used to remove any background processes that might get left behind after the Operator is stopped:

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

See the build/build.sh script for more.


## Miscellaneous

The following commands are useful to follow the progress during testing.  Run them in separate terminals. 

This command shows the controlled pods that are associated with the CR myapp1:

```
watch -n1 kubectl get po --selector=myapp=myapp1
```

These commands are used by the Operator to watch events related to the Operator (the CR and its child objects). Note that any child objects (pods) that the CR controls are labeled so they can be easily identified.

```
kubectl get myapp --watch --no-headers --ignore-not-found                           # watch the CR itself
kubectl get pod --selector=myapp=myapp1 --watch --no-headers --ignore-not-found  # watch all controlled resources 
```

You will need to create the CRD and the role with _cluster-admin_ permissions, otherwise you may see the following errors:

```
kubectl create -f deploy/crd-myapp.yaml
Error from server (Forbidden): error when creating "deploy/crd-myapp.yaml": customresourcedefinitions.apiextensions.k8s.io is forbidden: User "user0" cannot create resource "customresourcedefinitions" in API group "apiextensions.k8s.io" at the cluster scope
```
 
or

```
create -f deploy/role.yaml
Error from server (Forbidden): error when creating "deploy/role.yaml": roles.rbac.authorization.k8s.io "bash-operator" is forbidden...
```



