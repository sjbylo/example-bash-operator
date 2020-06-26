FROM docker.io/centos

RUN yum install -y jq 
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/`curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt`/bin/linux/amd64/kubectl && \
	chmod 755 kubectl && mv kubectl /usr/local/bin; 

COPY operator.sh .

USER 1001

CMD ./operator.sh 
#CMD kubectl get po
