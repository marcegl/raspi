#!/bin/bash

# Parámetros esperados
ROLE=$1            # 'master' o 'worker'
MASTER_IP=$2       # Dirección IP del nodo master (necesario para workers)
NODE_TOKEN=$3      # Token del nodo master (necesario para workers)

# Leer configuración del sistema (similar a ARM)
HOSTNAME=$(hostnamectl --static)
NODE_IP=$(ip route get 1.1.1.1 | grep -oP 'src \K\S+' 2>/dev/null)

# Fallback para obtener hostname e IP
if [ -z "$HOSTNAME" ]; then
    HOSTNAME=$(hostname)
fi

if [ -z "$NODE_IP" ]; then
    NODE_IP=$(hostname -I | awk '{print $1}')
fi

echo "Configuración detectada:"
echo "  Hostname: $HOSTNAME"
echo "  IP del nodo: $NODE_IP"

if [ "$ROLE" == "master" ]; then
    # Para master no se requieren parámetros adicionales
    echo "Configurando nodo master..."
elif [ "$ROLE" == "worker" ]; then
    if [ -z "$MASTER_IP" ] || [ -z "$NODE_TOKEN" ]; then
        echo "Uso para worker: $0 worker <MASTER_IP> <NODE_TOKEN>"
        echo "Ejemplo: $0 worker 192.168.123.85 K10abcd..."
        exit 1
    fi
    echo "Configurando nodo worker..."
else
    echo "El rol especificado es inválido. Usa 'master' o 'worker'."
    echo "Uso: $0 {master|worker} [<MASTER_IP> <NODE_TOKEN>]"
    exit 1
fi

# Verificar que es Ubuntu Server
if ! grep -q "Ubuntu" /etc/os-release; then
    echo "Este script está diseñado para Ubuntu Server 24.04"
    exit 1
fi

# Verificar conectividad de red
ping -c 3 8.8.8.8 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Error: No hay conectividad a internet. Verifique la configuración de red."
    exit 1
fi

# Verificar que curl está instalado
if ! command -v curl >/dev/null 2>&1; then
    echo "Instalando curl..."
    sudo apt-get update
    sudo apt-get install -y curl
fi

if [ "$ROLE" == "master" ]; then
    echo "Instalando K3s en el nodo master..."

    # Instalar K3s en el master con configuración optimizada para Ubuntu
    curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server" sh -s - \
        --disable=traefik \
        --disable=servicelb \
        --write-kubeconfig-mode 644 \
        --node-name="$HOSTNAME" \
        --node-ip="$NODE_IP" \
        --bind-address="$NODE_IP" \
        --advertise-address="$NODE_IP" \
        --cluster-cidr=10.42.0.0/16 \
        --service-cidr=10.43.0.0/16

    # Verificar instalación
    if [ $? -ne 0 ]; then
        echo "Error durante la instalación de K3s master"
        exit 1
    fi

    # Esperar a que K3s esté listo
    echo "Esperando que K3s esté listo..."
    sleep 15

    # Obtener el token del nodo master
    NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token 2>/dev/null)
    if [ -n "$NODE_TOKEN" ]; then
        echo "Token del nodo master: $NODE_TOKEN"
        echo "$NODE_TOKEN" > ~/k3s-node-token.txt
        chmod 600 ~/k3s-node-token.txt
        echo "Token guardado en ~/k3s-node-token.txt"
    else
        echo "Advertencia: No se pudo obtener el token del nodo master"
    fi

    # Configurar kubectl para el usuario actual
    mkdir -p ~/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
    sudo chown $(id -u):$(id -g) ~/.kube/config
    chmod 600 ~/.kube/config
    export KUBECONFIG=~/.kube/config

    # Configurar kubectl para root también
    sudo mkdir -p /root/.kube
    sudo cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

    # Agregar kubectl al PATH si no está
    if ! command -v kubectl >/dev/null 2>&1; then
        echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
        export PATH=$PATH:/usr/local/bin
    fi

    # Verificar el estado de K3s
    echo "=== Estado del servicio K3s ==="
    sudo systemctl status k3s --no-pager -l

    echo "=== Información del cluster ==="
    sleep 5
    kubectl get nodes -o wide
    kubectl get pods --all-namespaces

    echo "=== Configuración completada ==="
    echo "Master node configurado correctamente."
    echo "IP del master: $NODE_IP"
    echo "Token para workers guardado en: ~/k3s-node-token.txt"
    echo ""
    echo "Para agregar workers, use:"
    echo "./setup_post_reboot.sh worker $NODE_IP $NODE_TOKEN"

elif [ "$ROLE" == "worker" ]; then
    echo "Instalando K3s en un nodo worker..."

    # Verificar conectividad con el master
    echo "Verificando conectividad con el master ($MASTER_IP)..."
    nc -z "$MASTER_IP" 6443 || {
        echo "Error: No se puede conectar al master en $MASTER_IP:6443"
        echo "Verifique que el master esté funcionando y sea accesible."
        exit 1
    }

    # Instalar K3s en el worker
    curl -sfL https://get.k3s.io | K3S_URL="https://$MASTER_IP:6443" \
        K3S_TOKEN="$NODE_TOKEN" \
        INSTALL_K3S_EXEC="agent" \
        sh -s - \
        --node-name="$HOSTNAME" \
        --node-ip="$NODE_IP"

    # Verificar instalación
    if [ $? -ne 0 ]; then
        echo "Error durante la instalación de K3s worker"
        exit 1
    fi

    # Verificar el estado de K3s agent
    echo "=== Estado del servicio K3s Agent ==="
    sudo systemctl status k3s-agent --no-pager -l

    echo "=== Worker configurado correctamente ==="
    echo "Worker node: $HOSTNAME"
    echo "IP del worker: $NODE_IP"
    echo "Conectado al master: $MASTER_IP"
    echo ""
    echo "Verifique en el master con: kubectl get nodes"

fi

echo "=== Información de servicios ==="
echo "Para ver logs: sudo journalctl -u k3s -f"
echo "Para reiniciar: sudo systemctl restart k3s"
echo "Para desinstalar: /usr/local/bin/k3s-uninstall.sh"