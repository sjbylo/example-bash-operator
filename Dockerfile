FROM registry.access.redhat.com/ubi8/ubi-minimal
#FROM registry.redhat.io/ubi8/ubi-minimal

USER root

# Install jq for json parsing
RUN \
	microdnf install gzip tar && \
	curl -Lso /usr/local/bin/jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 && \
		chmod 755 /usr/local/bin/jq && \
	curl -so - https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz | \
		tar xzv -C /usr/local/bin -f - oc && \
		ln -s ./oc /usr/local/bin/kubectl && \
		chmod 755 /usr/local/bin/oc

# Set a location for the script, ensure kubectl can write to /.kube
WORKDIR /app
COPY operator.sh .
RUN mkdir /.kube && chmod -R 770 . /.kube

USER 1001

CMD LOGLEVEL=1 ./operator.sh 2>>log | tee -a log
