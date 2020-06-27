# Example Kubernetes Operator in bash

This simple Operator is written entirely in bash and shows how to create an Operator to manage a set of pods, similar to the way a typical Kubernetes replica-set works.  
It always ensures that the expected number of pods are running.

# Testing the Operator

The Operator can be tested by running it directly on a Linux machine or in a pod.  It has been tested on RHEL 7.5 and Fedora 32 and on Minishift and Kubernetes 1.17 (OpenShift 4.4)

Create and switch to a namespace:

```
kubectl create namespace operator-test
kubectl config set-context --current --namespace=operator-test
```

Create the Custom Resource Definition (CRD) and an example Custom Resource (CR):

```
kubectl create -f test/crd-myapp.yaml   # Do that as cluster-admin
kubectl create -f test/cr-myapp1.yaml
```

Have a look at the "myapp1" CR.  Note that "replica" is set to the required number of pods.

```
oc get myapp myapp1 -o yaml | grep replica
```

Now, decide to run the Operator on a Linux machine or in Kubernetes pod.

## Run the Operator in a pod

Launch the Operator:

```
oc run bash-op --generator=run-pod/v1 --image=quay.io/sjbylo/bash-operator:latest
```

To allow the Operator, running in a container, to access the Kubernetes API, this is one quick way of allowing it:

```
oc policy add-role-to-user cluster-admin -z default
```

# Start the Operator on a Linux machine

On the Linux machine, ensure kubectl is installed and authenticated with a Kubernetes or OpenShift cluster.  Also ensure that "jq" is installed on the Linux machine. 

Run the Operator:

```
./operator.sh 2>err.log; sleep 1; test/cleanup.sh    # Enter Ctr-C to stop it!
```

# Run some tests

A test script is provided that works by setting the CR replica value and by deleting and adding pods.  The number of pods should always be kept to the desired state by the Operator, as defined by .spec.replica in the CR.

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


# Miscellaneous

The following commands are useful to follow the progress during testing.  Run them in a separate terminal. 

This command shows the pods that are running:

```
cr=myapp1
watch -n1 "kubectl get po --selector=operator=$cr; ps -ef | grep 'kubectl get ' | grep -v ' watch' | grep -v grep"
```

These are the commands that are used by the Operator to set a watch on events related to the Operator (the CR and its pod child objects). Note 
that any child objects that the object manages are labeled so they they can be easily watched.

```
cr=myapp1
kubectl get pod --selector=operator=$cr --watch --no-headers --ignore-not-found
kubectl get myapp --watch --no-headers --ignore-not-found
```

# Work in progress

Note that, for testing purposes, it will not work on Mac OS (Darwin) until it's been fixed. Some of the commands in Mac OS work in different ways. 


