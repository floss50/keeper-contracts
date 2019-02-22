#!/bin/bash

curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl

mkdir -p ~/.kube
cat<<EOF > ~/.kube/config
apiVersion: v1
clusters:
- cluster:
    certificate-authority-data: ${KUBE_CERTIFICATE_AUTHORITY_DATA}
    server: ${KUBE_SERVER}
  name: cluster
contexts:
- context:
    cluster: cluster
    namespace: ${KUBE_NAMESPACE}
    user: ${KUBE_USER}
  name: cluster
current-context: cluster
kind: Config
preferences: {}
users:
- name: ${KUBE_USER}
  user:
    client-key-data: ${KUBE_CLIENT_KEY_DATA}
    token: ${KUBE_TOKEN}
EOF

subfilename=${TRAVIS_BRANCH//\//-}
subfilename=${subfilename//_/-}
mythril_name="mythril-${subfilename}"
mythril_name=${mythril_name:0:62}
securify_name="securify-${subfilename}"
securify_name=${securify_name:0:62}

# Check if there is jobs already running for this branch
if ! kubectl get pods -l analysis=mythril,branch=${subfilename} 2>&1 | grep -q Running; then
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${mythril_name}
  namespace: ${KUBE_NAMESPACE}
  labels:
    analysis: mythril
    branch: ${subfilename}
    travisjob: "${TRAVIS_JOB_ID}"
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: mythril-test
        image: "ubuntu:18.04"
        command:
        - /bin/entrypoint.sh
        - ${TRAVIS_BRANCH}
        volumeMounts:
        - name: script-volume
          mountPath: /bin/entrypoint.sh
          readOnly: true
          subPath: entrypoint.sh
        - name: sshkey
          readOnly: true
          mountPath: "/etc/ssh_key"
      volumes:
      - name: script-volume
        configMap:
          defaultMode: 0777
          name: keeper-contract-mythril-analysis
      - name: sshkey
        secret:
          defaultMode: 0600
          secretName: sshkey
EOF
fi

if ! kubectl get pods -l analysis=securify,branch=${subfilename} 2>&1 | grep -q Running; then
  cat <<EOF | kubectl apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${securify_name}
  namespace: ${KUBE_NAMESPACE}
  labels:
    analysis: securify
    branch: ${subfilename}
    travisjob: "${TRAVIS_JOB_ID}"
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: securify
        image: "chainsecurity/securify:latest"
        command:
        - /bin/entrypoint.sh
        - ${TRAVIS_BRANCH}
        volumeMounts:
        - name: script-volume
          mountPath: /bin/entrypoint.sh
          readOnly: true
          subPath: entrypoint.sh
        - name: sshkey
          readOnly: true
          mountPath: "/etc/ssh_key"
      volumes:
      - name: script-volume
        configMap:
          defaultMode: 0777
          name: keeper-contract-securify-analysis
      - name: sshkey
        secret:
          defaultMode: 0600
          secretName: sshkey
EOF
else
  echo "securify-analysis-${subfilename}-${TRAVIS_JOB_ID}"
fi

