# Some useful commands for developing and testing this operator

Build, tag, push and run the tests.  Use your own image repo!

[test](http://google.com){:target="_blank"}

```
docker build -t bash_operator . && \
  docker tag bash_operator quay.io/sjbylo/bash-operator:dev && \
  docker push quay.io/sjbylo/bash-operator:dev && \
  test/startall.sh 1 dev
```

View the operator logs:

```
kubectl logs bash-operator -f 
```

Run the tests once, using the "dev" tag, with highest log level (2)

```
test/startall.sh 1 dev 2
```

See the test/startall.sh script for more.

Run the operator with full log level:

```
kubectl run bash-operator --env=LOGLEVEL=2 --image-pull-policy=Always --image=quay.io/sjbylo/bash-operator:dev
kubectl create -f deploy/cr-myapp1.yaml
test/test.sh myapp1
```

View the Operator's logs:

```
test/logs.sh 
```

The cluster wide CRD cannot be deleted until all CR objects within the cluster have been deleted. Normally, the Operator would detect the deletion of a CR, delete the controlled pods and then allow the CR to be garbage collected.  If that goes wrong, here is how to removing a finalizer in a CR:

```
kubectl patch ma myapp1 --type=merge -p '{"metadata": {"finalizers":null}}'
```

