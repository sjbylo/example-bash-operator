FROM docker.io/centos

USER root

RUN yum install -y jq && yum clean all -y

RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && \
	chmod 755 kubectl && mv kubectl /usr/local/bin; 

#ENV HOME /app
RUN mkdir /.kube
WORKDIR /app
COPY operator.sh .
RUN chmod -R 777 . /.kube

USER 1001

CMD ./operator.sh 
#CMD kubectl get po
