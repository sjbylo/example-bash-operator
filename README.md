# Example Kubernetes Operator in bash

This simple Operator is written entirely in bash and shows how to create an Operator to manage a set of pods.  It works in a similar to the way a typical Kubernetes replica-set works, it always ensures that the specified number of pods are running.

# Getting started

First, create a namespace and switch to it:

```
kubectl create namespace operator-test
kubectl config set-context --current --namespace=operator-test
```

## Test the Operator using the provided scripts

The quick way to test this is to run the following commands in seperate terminals:

```
test/runall.sh 1            # run one itteration of the tests from quay.io/sjbylo/bash-operator:latest
test/runall.sh 2 latest     # run all tests for two custom resources in parrallel from quay.io/sjbylo/bash-operator:dev 
```
(See the runall.sh file for more options) 

## View what's happening in a seperate terminal

```
watch kubectl get pods
```

# Testing the Operator

The Operator can be tested by running it directly on a Linux machine or on Kubernetes.  It has been tested on the following: RHEL 7.5, Fedora 32, Minikube, Kubernetes 1.17 and OpenShift 4.4.


As cluster-admin, create the Custom Resource Definition (CRD) and an example Custom Resource (CR):

```
kubectl create -f test/crd-myapp.yaml  
kubectl create -f test/cr-myapp1.yaml
```

Have a look at the "myapp1" Customer Resource.  Note that "replica" is set to the required number of pods.

```
kubectl get myapp myapp1 -o yaml | grep replica
```

Now, decide to run the Operator either on a Linux machine or in Kubernetes.


## Start the Operator in Kubernetes

To allow the Operator to access the Kubernetes API, use the manefests in the deploy directory:

```
kubectl create -f deploy/service_account.yaml
kubectl create -f deploy/role.yaml
kubectl create -f deploy/role_binding.yaml
```

Launch the Operator as a deployment:

```
kubectl create -f deploy/operator.yaml
```

... or launch the Operator as a pod:

```
kubectl run bash-operator --generator=run-pod/v1 --image=quay.io/sjbylo/bash-operator:latest
```

View the log output:

```
while true; do kubectl logs bash-operator -f; sleep 1; done
```

Stop the Operator:

```
kubectl delete po bash-operator
```

Alternatively, instead of using "kubectl run", you can create a deployment:

```
kubectl create deployment bash-operator --image=bash-operator
```


## Start the Operator on a Linux machine

On the Linux machine, ensure kubectl is installed and authenticated with a Kubernetes or OpenShift cluster.  Also ensure that "jq" is installed.

Run the Operator:

```
./operator.sh 2>err.log; sleep 1; test/cleanup.sh    # Enter Ctr-C to stop it!
```

# Run some tests

A test script is provided that works by setting the CR replica value and by deleting and adding pods.  The Operator will ensure that the correct number of pods are always running, as defined by .spec.replica in the CR.

Start the test script in a different terminal:

```
test/test.sh myapp1
```

A cleanup script can be used to remove any background processes that might get left behind after the Operator is stopped:

```
test/cleanup.sh
```

# Dockerfile

A dockerfile is provided to build a container image for the Operator. 

Here is an example of building the image:

```
docker build -t bash_operator . && \
docker tag  bash_operator  quay.io/sjbylo/bash-operator  && \
docker push quay.io/sjbylo/bash-operator 
```

# Miscellaneous

The following commands are useful to follow the progress during testing.  Run them in a separate terminal. 

This command shows the pods that are running:

```
cr=myapp1  # Set the name of your Custom Resource
watch -n1 "kubectl get po --selector=operator=$cr; ps -ef | grep 'kubectl get ' | grep -v ' watch' | grep -v grep"
```

These are the commands that are used by the Operator to set a watch on events related to the Operator (the CR and its child objects). Note that any child objects that the object manages are labeled so they they can be easily watched.

```
cr=myapp1
kubectl get pod --selector=operator=$cr --watch --no-headers --ignore-not-found
kubectl get myapp --watch --no-headers --ignore-not-found
```

# Work in progress

Note that, for testing purposes, it will not work on Mac OS (Darwin) until it's been fixed. Some of the commands in Mac OS work in different ways. 


