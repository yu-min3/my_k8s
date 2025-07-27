
# CRI-Oランタイムインストール

## 設定変更してreboot
sudo nano /boot/firmware/cmdline.txt
root=...  ← 既存のカーネル引数
+ cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1
reboot



## master node
export KUBERNETES_VERSION=v1.33
export CRIO_VERSION=v1.33
https://github.com/cri-o/packaging/blob/main/README.md/

export KUBECONFIG=/etc/kubernetes/admin.conf
kubeadm init --pod-network-cidr=10.244.0.0/16

kubeadm join 192.168.0.107:6443 --token ahqo5q.tafg2lwyufh8o6tp \
        --discovery-token-ca-cert-hash sha256:77aae9c48a2d5b34777af69a33e2ea27506fbfe7a24776793358dd9742ba28e3

## worker node
master nodeで出てきたjoinを適用

# CNI install
https://docs.tigera.io/calico/latest/getting-started/kubernetes/self-managed-onprem/onpremises

## docker registryの登録
gatewayのIPをhost解決
echo "192.168.0.240 registry.local" >> /etc/hosts