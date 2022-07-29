#!/bin/bash

## !IMPORTANT ##
#
## This script is tested only in the generic/ubuntu2004 Vagrant box
## If you use a different version of Ubuntu or a different Ubuntu Vagrant box test this again
#

echo "********Preparaing the operating system********"

# rm -f /etc/localtime
# ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
# ln -sf /usr/share/zoneinfo/Etc/UTC /etc/localtime
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# replace the ubuntu official repo with tsinghua mirror
cat >/etc/apt/sources.list<<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-updates main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-backports main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-security main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-security main restricted universe multiverse
# deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-proposed main restricted universe multiverse
# deb-src https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ focal-proposed main restricted universe multiverse
EOF

# use aliyun mirror for kubernetes to bypass the gfw
curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add - >/dev/null 2>&1
# apt-add-repository "deb https://mirrors.aliyun.com/kubernetes/apt kubernetes-xenial main" >/dev/null 2>&1
# apt-add-repository "deb https://mirrors.tuna.tsinghua.edu.cn/kubernetes/apt kubernetes-xenial main" >/dev/null 2>&1

cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF

apt update >/dev/null 2>&1

apt upgrade -y >/dev/null 2>&1
apt autoremove -y >/dev/null 2>&1

echo "[TASK 1] Disable and turn off SWAP"
sed -i '/swap/d' /etc/fstab
swapoff -a

echo "[TASK 2] Stop and Disable firewall"
systemctl disable --now ufw >/dev/null 2>&1

echo "[TASK 3] Enable and Load Kernel modules"
cat >>/etc/modules-load.d/containerd.conf<<EOF
overlay
br_netfilter
EOF
modprobe overlay
modprobe br_netfilter

echo "[TASK 4] Add Kernel settings"
# cat >>/etc/sysctl.d/99-kubernetes-cri.conf<<EOF
cat >>/etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
EOF
sysctl --system >/dev/null 2>&1

echo "[TASK 5] Install containerd runtime"
apt update -qq >/dev/null 2>&1
apt install -qq -y containerd apt-transport-https >/dev/null 2>&1
[ ! -d /etc/containerd ] && mkdir /etc/containerd
containerd config default > /etc/containerd/config.toml

# # https://registry.cn-hangzhou.aliyuncs.com
# sed -i "s#k8s.gcr.io#registry.aliyuncs.com/google_containers#g" /etc/containerd/config.toml
# sed -i "s#https://registry-1.docker.io#https://registry.aliyuncs.com#g" /etc/containerd/config.toml
# sed -i "s#SystemdCgroup = false#SystemdCgroup = true#g" /etc/containerd/config.toml

# # sed -i '/containerd.runtimes.runc.options/a\ \ \ \ \ \ \ \ \ \ \ \ SystemdCgroup = true' /etc/containerd/config.toml

[ ! -d /etc/systemd/system/containerd.service.d ] && mkdir /etc/systemd/system/containerd.service.d
cat <<EOF >/etc/systemd/system/containerd.service.d/http-proxy.conf
[Service]
Environment="HTTP_PROXY=${HTTP_PROXY}"
Environment="HTTPS_PROXY=${HTTPS_PROXY}"
Environment="NO_PROXY=${NO_PROXY}"
EOF
systemctl daemon-reload
systemctl restart containerd
systemctl enable containerd >/dev/null 2>&1

echo "[TASK 6] Add apt repo for kubernetes"
# curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add - >/dev/null 2>&1
# apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main" >/dev/null 2>&1

echo "[TASK 7] Install Kubernetes components (kubeadm, kubelet and kubectl)"
# apt install -qq -y kubeadm=1.19.16-00 kubelet=1.19.16-00 kubectl=1.19.16-00 >/dev/null 2>&1
# apt install -qq -y kubeadm=1.20.14-00 kubelet=1.20.14-00 kubectl=1.20.14-00 >/dev/null 2>&1
# apt install -qq -y kubeadm=1.21.8-00 kubelet=1.21.8-00 kubectl=1.21.8-00 >/dev/null 2>&1
# apt install -qq -y kubeadm=1.22.5-00 kubelet=1.22.5-00 kubectl=1.22.5-00 >/dev/null 2>&1
# apt install -qq -y kubeadm=1.23.9-00 kubelet=1.23.9-00 kubectl=1.23.9-00 >/dev/null 2>&1
apt install -qq -y kubeadm=1.24.3-00 kubelet=1.24.3-00 kubectl=1.24.3-00 >/dev/null 2>&1

# pin their version to avoid upgrade
apt-mark hold kubelet kubeadm kubectl

echo "[TASK 8] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
systemctl reload sshd

echo "[TASK 9] Set root password"
echo -e "kubeadmin\nkubeadmin" | passwd root >/dev/null 2>&1
echo "export TERM=xterm" >> /etc/bash.bashrc

echo "[TASK 10] Update /etc/hosts file"
cat >>/etc/hosts<<EOF
172.16.16.100   kmaster.example.com     kmaster
172.16.16.101   kworker1.example.com    kworker1
172.16.16.102   kworker2.example.com    kworker2
EOF
