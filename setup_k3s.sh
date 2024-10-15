#!/bin/bash

# Parámetros esperados
ROLE=$1            # 'master' o 'worker'
HOSTNAME=$2        # Hostname para el Raspberry Pi
MASTER_IP=$3       # Dirección IP del nodo master (necesario para workers)
NODE_TOKEN=$4      # Token del nodo master (necesario para workers)

# Asegurarse de que el sistema esté actualizado
sudo apt-get update && sudo apt-get upgrade -y

# Configurar el hostname sin reiniciar
sudo hostnamectl set-hostname "$HOSTNAME"
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $HOSTNAME/g" /etc/hosts
echo "Hostname configurado en: $HOSTNAME"

# Deshabilitar swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Configurar cgroups si no están configurados
CGROUP_PARAMS="cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
if ! grep -q "cgroup_enable" /boot/cmdline.txt; then
    sudo sed -i "1 s|$| $CGROUP_PARAMS|" /boot/cmdline.txt
fi

# Instalar y configurar fail2ban
sudo apt-get install -y fail2ban
sudo bash -c 'cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime  = 10m
maxretry = 5
[sshd]
enabled = true
EOF'
sudo systemctl restart fail2ban

# Configuración de forwarding de IP
sudo sysctl -w net.ipv4.ip_forward=1
if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
fi

# Configuración de rendimiento
if ! grep -q "dtparam=audio=off" /boot/config.txt; then
    echo "dtparam=audio=off" | sudo tee -a /boot/config.txt
fi
sudo sysctl -w net.core.rmem_max=2500000
sudo sysctl -w net.core.wmem_max=2500000
sudo sysctl -w net.core.netdev_max_backlog=5000
sudo sed -i 's/errors=remount-ro/noatime,errors=remount-ro/' /etc/fstab

# Instalar iptables para asegurar que K3s funcione correctamente
sudo apt-get install -y iptables

# Instalar K3s basado en el rol
if [ "$ROLE" == "master" ]; then
    echo "Instalando K3s en el nodo master..."

    # Obtener la dirección IP del nodo
    NODE_IP=$(hostname -I | awk '{print $1}')

    # Instalar K3s en el master con opciones específicas
    curl -sfL https://get.k3s.io | sh -s - server \
        --disable=traefik \
        --disable=servicelb \
        --write-kubeconfig-mode 644 \
        --node-name="$HOSTNAME" \
        --node-ip="$NODE_IP" \
        --bind-address="$NODE_IP" \
        --advertise-address="$NODE_IP"

    # Obtener el token del nodo master
    NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
    echo "Token del nodo master: $NODE_TOKEN"
    echo "$NODE_TOKEN" > ~/k3s-node-token.txt

    # Configurar kubectl para el usuario actual
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config

    # Verificar el estado de K3s
    sudo systemctl status k3s
    kubectl get nodes

elif [ "$ROLE" == "worker" ]; then
    echo "Instalando K3s en un nodo worker..."

    if [ -z "$MASTER_IP" ] || [ -z "$NODE_TOKEN" ]; then
        echo "Por favor, proporciona la IP del master y el NODE_TOKEN obtenido del nodo master."
        exit 1
    fi

    # Obtener la dirección IP del nodo
    NODE_IP=$(hostname -I | awk '{print $1}')

    # Instalar K3s en el worker
    curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" \
        K3S_TOKEN="$NODE_TOKEN" \
        sh -s - agent \
        --node-name="$HOSTNAME" \
        --node-ip="$NODE_IP"

    # Verificar el estado de K3s
    sudo systemctl status k3s-agent

else
    echo "El rol especificado es inválido. Usa 'master' o 'worker'."
    exit 1
fi