# Some useful commands for developing and testing this operator

Build, tag, push and run the tests.  Use your own image repo!

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

Run the tests once, using the dev tag, with highest log level

```
test/startall.sh 1 dev 2
```
See the test/startall.sh for more

Run the operator with full log level

```
kubectl run bash-operator --env=LOGLEVEL=2 --generator=run-pod/v1 --image-pull-policy=Always --image=quay.io/sjbylo/bash-operator:dev
kubectl create -f test/cr-myapp1.yaml
test/test.sh myapp1
```

View the Operator's logs:

```
test/logs.sh 
```


