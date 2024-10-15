#!/bin/bash

# Parámetros esperados
ROLE=$1  # 'master' o 'worker'
IP_SUFFIX=$2  # Por ejemplo, '201' para 192.168.123.201
MASTER_SUFFIX=${3:-"201"}  # Sufijo de la IP del nodo master, por defecto 201
NODE_TOKEN=$4  # Token del nodo master (obligatorio para workers)
HOSTNAME=$5  # Hostname para el Raspberry Pi

# Asegurarse de que el sistema esté actualizado
sudo apt-get update && sudo apt-get upgrade -y

# Configurar el hostname sin reiniciar
sudo hostnamectl set-hostname $HOSTNAME
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $HOSTNAME/g" /etc/hosts
echo "Hostname configurado en: $HOSTNAME"

# Verificar si dhcpcd está instalado, si no, instalarlo
if ! dpkg -l | grep -q dhcpcd; then
    echo "dhcpcd no está instalado. Procediendo a instalar..."
    sudo apt-get install -y dhcpcd5
    sudo systemctl enable dhcpcd
else
    echo "dhcpcd ya está instalado."
fi

# Configuración de IP fija con dhcpcd
sudo bash -c "cat <<EOF >> /etc/dhcpcd.conf
interface eth0
static ip_address=192.168.123.${IP_SUFFIX}/24
static routers=192.168.123.1
static domain_name_servers=192.168.123.1 8.8.8.8
EOF"

sudo systemctl restart dhcpcd
IP_ASSIGNED=$(hostname -I | awk '{print $1}')
echo "IP asignada: $IP_ASSIGNED"

# Configuración de cgroups y desactivación de swap
sudo sed -i 's/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/' /boot/cmdline.txt
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Instalar y configurar fail2ban
sudo apt-get install -y fail2ban
sudo bash -c "cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime  = 10m
maxretry = 5
[sshd]
enabled = true
EOF"
sudo systemctl restart fail2ban

# Configuración de forwarding de IP
sudo sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf

# Configuración de rendimiento
sudo echo "dtparam=audio=off" | sudo tee -a /boot/config.txt
sudo sysctl -w net.core.rmem_max=2500000
sudo sysctl -w net.core.wmem_max=2500000
sudo sysctl -w net.core.netdev_max_backlog=5000
sudo sed -i '/ \/ / s/errors=remount-ro/noatime,errors=remount-ro/' /etc/fstab

# Instalar iptables para asegurar que K3s funcione correctamente
sudo apt-get install -y iptables

# Instalar K3s basado en el rol
if [ "$ROLE" == "master" ]; then
    echo "Instalando K3s en el nodo master..."
    curl -sfL https://get.k3s.io | sh -s - server --disable=traefik --disable=servicelb --write-kubeconfig-mode 644 --node-name "$(hostname)"
    NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
    echo "Token del nodo master: $NODE_TOKEN"
    echo "$NODE_TOKEN" > ~/k3s-node-token.txt
else
    echo "Instalando K3s en un nodo worker..."
    if [ -z "$NODE_TOKEN" ]; then
        echo "Por favor, proporciona el NODE_TOKEN obtenido del nodo master."
        exit 1
    fi
    curl -sfL https://get.k3s.io | K3S_URL="https://192.168.123.${MASTER_SUFFIX}:6443" K3S_TOKEN="${NODE_TOKEN}" sh -
fi

# Verificar el estado de K3s
sudo systemctl status k3s
kubectl get nodes
