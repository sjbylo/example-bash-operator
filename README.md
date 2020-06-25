# Simple example operator in bash

This simple operator, written in bash, shows how to create an operator to manage a set of pods, similar how a replica set works.   

# Test it by running it locally

The operator can be tested by running it on your Linux machine.  It has been tested on RHEL 7.5 and Fedora 32. Note that it does not work on Mac OS (Darwin).  

Ensure kubectl is authenticated with a Kube test cluster.

First, create the Custom Resource Definition and an example Custom Resource:

```
kubectl create -f test/crd-myapp.yaml
kubectl create -f test/cr-myapp1.yaml
```

Start the operator:

```
operator.sh   # Hit Ctr-C to stop it!
```

Start the test script:

```
test/test.sh
```

This command can be used to clean up any background processes:

```
kill `ps -ef | grep op.sh| grep -v -e grep -e vi | awk '{$3 == 1; print $2}'`
```

# Miscellaneous

The following commands might be useful to follow what is happening.  Run them in separate terminal. 

```
watch -n1 "kubectl get po; ps -ef | grep 'kubectl get ' | grep -v ' watch' | grep -v grep"
```

# Commands used to set a watch on events related to this operator (the CR and its pod child objects)

```
cr=myapp
kubectl get pod --selector=operator=$cr --watch --no-headers --ignore-not-found
kubectl get myapp --watch --no-headers --ignore-not-found
```

```
cr=myapp
watch -n1 "kubectl get po --selector=operator=$cr; ps -ef | grep 'kubectl get ' | grep -v ' watch' | grep -v grep"
do kubectl get pod --selector=operator=$cr --watch --no-headers --ignore-not-found
```

