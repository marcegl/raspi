#!/bin/bash

# Parámetros esperados
ROLE=$1            # 'master' o 'worker'
IP_ADDRESS=$2      # Dirección IP estática, por ejemplo, '192.168.1.85/24'
HOSTNAME=$3        # Hostname para el Raspberry Pi
MASTER_IP=$4       # Dirección IP del nodo master (necesario para workers)
NODE_TOKEN=$5      # Token del nodo master (necesario para workers)

# Obtener la dirección IP del nodo (debería ser la IP estática configurada)
NODE_IP="${IP_ADDRESS%/*}"

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
