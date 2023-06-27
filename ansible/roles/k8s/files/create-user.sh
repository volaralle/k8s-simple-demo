#!/bin/bash

if [ "$2" != "" ]; then
company=$2
else
company=your-company-name
fi

if [ "$3" != "" ]; then
namespace=$3
else
namespace=default
fi

openssl genrsa -out user-$1.key 2048
openssl req -new -key user-$1.key -out user-$1.csr -subj "/CN=$1/O=$company"
openssl x509 -req -in user-$1.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out user-$1.crt -days 5000

rm user-$1.csr

cacrt=$(cat /etc/kubernetes/pki/ca.crt | base64 | tr -d '\n')
crt=$(cat user-$1.crt | base64 | tr -d '\n')
key=$(cat user-$1.key | base64 | tr -d '\n')

cat <<EOM >user-$1.config
apiVersion: v1
kind: Config
users:
- name: $1
  user:
    client-certificate-data: $crt
    client-key-data: $key
clusters:
- cluster:
    certificate-authority-data: $cacrt
    server: $5
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    namespace: $namespace
    user: $1
  name: $1-context@kubernetes
current-context: $1-context@kubernetes
EOM

if [ "$4" != "" ]; then
kubectl config set-credentials $1 --client-certificate=user-$1.crt  --client-key=user-$1.key
kubectl config set-context $1-context --cluster=kubernetes --namespace=$namespace --user=$1
else
rm user-$1.crt
rm user-$1.key
fi

cat <<EOM >user-$1.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: $namespace
  name: pod-reader
rules:
- apiGroups: [""] # "" indicates the core API group
  resources: ["pods","pods/log","services","ingress","configmaps"]
  verbs: ["get", "watch", "list", "exec"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
---

apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-$1
  namespace: $namespace
subjects:
- kind: User
  name: $1
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOM

kubectl apply -f user-$1.yaml

rm user-$1.yaml
