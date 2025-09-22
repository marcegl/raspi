#!/bin/bash

# Parámetros esperados
ROLE=$1            # 'master' o 'worker'
MASTER_IP=$2       # Dirección IP del nodo master (necesario para workers)
NODE_TOKEN=$3      # Token del nodo master (necesario para workers)

# Leer configuración del sistema
HOSTNAME=$(hostnamectl --static)
NODE_IP=$(grep "static ip_address" /etc/dhcpcd.conf | tail -1 | awk '{print $3}' | cut -d'/' -f1)

if [ -z "$HOSTNAME" ]; then
    HOSTNAME=$(hostname)
fi

if [ -z "$NODE_IP" ]; then
    NODE_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+')
fi

echo "Configuración detectada:"
echo "  Hostname: $HOSTNAME"
echo "  IP del nodo: $NODE_IP"

if [ "$ROLE" == "master" ]; then
    echo "Instalando K3s en el nodo master..."

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
        echo "Uso: $0 worker <MASTER_IP> <NODE_TOKEN>"
        echo "Por favor, proporciona la IP del master y el NODE_TOKEN obtenido del nodo master."
        exit 1
    fi

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
