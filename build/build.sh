#!/bin/bash
# Build image and tag either :dev or :latest

[ "`git rev-parse --abbrev-ref HEAD`" = "master" ] && tag=latest || tag=dev
h=quay;
set -x;docker build -t bash_operator:$tag . && docker tag bash_operator:$tag $h.io/sjbylo/bash-operator:$tag && docker push $h.io/sjbylo/bash-operator:$tag; set +
