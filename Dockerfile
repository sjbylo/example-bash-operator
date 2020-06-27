FROM docker.io/centos

USER root

# Install jq for json parsing
RUN yum install -y jq && yum clean all -y

# Install latest kubectl
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && \
	chmod 755 kubectl && mv kubectl /usr/local/bin; 

# Set a location for the script, ensure kubectl can write to /.kube
WORKDIR /app
COPY operator.sh .
RUN mkdir /.kube && chmod -R 777 . /.kube

USER 1001

CMD ./operator.sh 
