#!/bin/bash

kill `ps -ef | grep -e operator.sh -e kubectl -e test.sh | grep -v -e grep -e vi | awk '{$3 == 1; print $2}'`

