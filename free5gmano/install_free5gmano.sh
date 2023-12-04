# free5gmano
git clone https://github.com/free5gmano/free5gmano.git
cd ./free5gmano
git checkout -b 3.1.1 eda01dbdd339f333caefbafe3424f2528e019432
# cd ./deploy/free5gc-stage-3.1.1
# sudo sed -i '/- kube-apiserver/a \ \ \ \ - --feature-gates=SCTPSupport=True' /etc/kubernetes/manifests/kube-apiserver.yaml
# kubectl apply -f 03-free5gc-nrf.yaml; sleep 10; kubectl apply -f .
# kube5gnfvo
git clone https://github.com/free5gmano/kube5gnfvo.git
cd kube5gnfvo/example/
kubectl apply -f multus-daemonset.yml
#openvswitch
sudo apt install openvswitch-switch -y
sudo ovs-vsctl add-br br1
# ovs-cni
cd ../..
cd kube5gnfvo/example/
kubectl apply -f ovs-cni.yaml
kubectl apply -f ovs-net-crd.yaml

# etcd operator
cd ../..
cd kube5gnfvo/example/etcd-cluster/rbac/
./create_role.sh
cd ..
kubectl apply -f deployment.yaml
sleep 10
kubectl apply -f ./

# metrics
cd ../../..
cd kube5gnfvo/example/metrics-server/
kubectl apply -f ./

# node exporter
cd ../../..
cd kube5gnfvo/example/
kubectl apply -f prom-node-exporter.yaml

# kubevirt
cd ../..
cd kube5gnfvo/example/kubevirt/
kubectl apply -f kubevirt-operator.yaml
sleep 10
kubectl apply -f kubevirt-cr.yaml

# kubevirt-py
sudo apt install python3-pip -y
pip3 install git+https://github.com/yanyan8566/client-python

# Quick start
# Create a Configmap that is based on a Config of kubernetes cluster
cat <<EOF >./kube5gnfvo-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube5gnfvo-config
data:
  config: |
$(sed 's/^/    /' ~/.kube/config)
EOF
kubectl apply -f kube5gnfvo-configmap.yaml
# Create kube5gnfvo ServiceAccount
cat <<EOF >./kube5gnfvo-sa.yaml
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: kube5gnfvo
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kube5gnfvo
  namespace: default
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: kube5gnfvo
EOF

kubectl apply -f kube5gnfvo-sa.yaml
# Deploy Mysql Database
cat <<EOF >./kube5gnfvo-mysql.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube5gnfvo-mysql
spec:
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: kube5gnfvo-mysql
  template:
    metadata:
      labels:
        app: kube5gnfvo-mysql
    spec:
      containers:
      - image: mysql:5.6
        name: kube5gnfvo-mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: password
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: kube5gnfvo-mysql
          mountPath: /var/lib/mysql
        volumeMounts:
        - name: mysql-initdb
          mountPath: /docker-entrypoint-initdb.d
      volumes:
      - name: kube5gnfvo-mysql
        persistentVolumeClaim:
          claimName: kube5gnfvo-mysql
      volumes:
      - name: mysql-initdb
        configMap:
          name: mysql-initdb-config
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kube5gnfvo-mysql
  labels:
    name: kube5gnfvo-mysql
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    type: DirectoryOrCreate
    path: /mnt/kube5gnfvo-mysql
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kube5gnfvo-mysql
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  selector:
    matchExpressions:
    - key: name
      operator: In
      values: ["kube5gnfvo-mysql"]
---
apiVersion: v1
kind: Service
metadata:
  name: kube5gnfvo-mysql
spec:
  ports:
  - port: 3306
  selector:
    app: kube5gnfvo-mysql
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: mysql-initdb-config
data:
  initdb.sql: |
    CREATE DATABASE kube5gnfvo;
EOF

kubectl apply -f kube5gnfvo-mysql.yaml
# Deploy kube5gnfvo
cat <<EOF >./kube5gnfvo.yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube5gnfvo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: kube5gnfvo
  template:
    metadata:
      labels:
        app: kube5gnfvo
    spec:
      serviceAccountName: kube5gnfvo
      containers:
      - image: free5gmano/kube5gnfvo-stage2
        name: kube5gnfvo
        env:
        - name: DATABASE_PASSWORD
          value: "password"
        - name: DATABASE_HOST
          value: "kube5gnfvo-mysql"
        - name: DATABASE_PORT
          value: "3306"
        command: ["/bin/sh","-c"]
        args: ['python3 manage.py migrate && python3 manage.py runserver 0:8000']
        ports:
        - containerPort: 8000
          name: kube5gnfvo
        volumeMounts:
        - name: kube5gnfvo-vnf-package
          mountPath: /root/NSD
          subPath: NSD
        - name: kube5gnfvo-vnf-package
          mountPath: /root/VnfPackage
          subPath: VnfPackage
        - name: kube-config
          mountPath: /root/config
          subPath: config
      volumes:
      - name: kube5gnfvo-vnf-package
        persistentVolumeClaim:
          claimName: kube5gnfvo-pvc
      - name: kube-config
        configMap:
          name: kube5gnfvo-config
          items:
          - key: config
            path: config
---
apiVersion: v1
kind: Service
metadata:
  name: kube5gnfvo
spec:
  type: NodePort
  ports:
  - port: 8000
    nodePort: 30888
  selector:
    app: kube5gnfvo
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: kube5gnfvo-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  selector:
    matchExpressions:
    - key: name
      operator: In
      values: ["kube5gnfvo"]
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: kube5gnfvo-pv
  labels:
    name: kube5gnfvo
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    type: DirectoryOrCreate
    path: /mnt/kube5gnfvo
EOF

kubectl apply -f kube5gnfvo.yaml

# deploy free5gmano
cd ../..
cd free5gmano/deploy
kubectl apply -f .
