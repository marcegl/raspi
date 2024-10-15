#!/bin/bash

# Parámetros esperados
ROLE=$1            # 'master' o 'worker'
IP_ADDRESS=$2      # Dirección IP estática, por ejemplo, '192.168.1.85/24'
GATEWAY=$3         # Dirección IP del gateway, por ejemplo, '192.168.1.254'
HOSTNAME=$4        # Hostname para el Raspberry Pi
MASTER_IP=$5       # Dirección IP del nodo master (necesario para workers)
NODE_TOKEN=$6      # Token del nodo master (necesario para workers)

# Verificar que se proporcionaron los parámetros necesarios
if [ -z "$ROLE" ] || [ -z "$IP_ADDRESS" ] || [ -z "$GATEWAY" ] || [ -z "$HOSTNAME" ]; then
    echo "Uso: $0 <master|worker> <IP_ADDRESS/CIDR> <GATEWAY> <HOSTNAME> [MASTER_IP] [NODE_TOKEN]"
    exit 1
fi

# Asegurarse de que el sistema esté actualizado
sudo apt-get update && sudo apt-get upgrade -y

# Configurar el hostname sin reiniciar
sudo hostnamectl set-hostname "$HOSTNAME"
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $HOSTNAME/g" /etc/hosts
echo "Hostname configurado en: $HOSTNAME"

# Configurar IP estática en /etc/dhcpcd.conf
sudo bash -c "cat >> /etc/dhcpcd.conf <<EOF

interface eth0
static ip_address=$IP_ADDRESS
static routers=$GATEWAY
static domain_name_servers=$GATEWAY 8.8.8.8
EOF"
echo "Configuración de IP estática aplicada."

# Reiniciar el servicio de red para aplicar cambios
sudo systemctl restart dhcpcd
echo "Servicio de red reiniciado."

# Esperar a que la interfaz de red esté activa con la nueva IP
echo "Esperando a que la interfaz eth0 tenga la nueva IP..."
while ! ip addr show eth0 | grep -q "${IP_ADDRESS%/*}"; do
    sleep 1
done
echo "La interfaz eth0 tiene la IP $IP_ADDRESS"

# Deshabilitar swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab
echo "Swap deshabilitado."

# Configurar cgroups si no están configurados
CGROUP_PARAMS="cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
if ! grep -q "cgroup_enable" /boot/cmdline.txt; then
    sudo sed -i "1 s|$| $CGROUP_PARAMS|" /boot/cmdline.txt
    echo "Parámetros de cgroup añadidos a /boot/cmdline.txt"
else
    echo "Parámetros de cgroup ya están configurados en /boot/cmdline.txt"
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
echo "Fail2ban instalado y configurado."

# Configuración de forwarding de IP
sudo sysctl -w net.ipv4.ip_forward=1
if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
fi
echo "IP forwarding configurado."

# Configuración de rendimiento
if ! grep -q "dtparam=audio=off" /boot/config.txt; then
    echo "dtparam=audio=off" | sudo tee -a /boot/config.txt
fi
sudo sysctl -w net.core.rmem_max=2500000
sudo sysctl -w net.core.wmem_max=2500000
sudo sysctl -w net.core.netdev_max_backlog=5000
sudo sed -i 's/errors=remount-ro/noatime,errors=remount-ro/' /etc/fstab
echo "Parámetros de rendimiento configurados."

# Instalar iptables para asegurar que K3s funcione correctamente
sudo apt-get install -y iptables

# Reiniciar para aplicar cambios de cgroups y otros
echo "Reiniciando el sistema para aplicar cambios..."
sudo reboot

# El script se detendrá aquí debido al reinicio
# Las siguientes acciones deben ejecutarse después del reinicio

# Esperar a que el sistema se reinicie
sleep 60

# Reanudar el script después del reinicio
# Debes ejecutar el script nuevamente después del reinicio usando un indicador para continuar
if [ -f /tmp/post_reboot_flag ]; then
    echo "Continuando con la instalación de K3s después del reinicio."
else
    echo "Iniciando reinicio para aplicar cambios. Por favor, ejecuta el script nuevamente después de que el sistema se haya reiniciado."
    touch /tmp/post_reboot_flag
    exit 0
fi

# Instalar K3s basado en el rol
if [ "$ROLE" == "master" ]; then
    echo "Instalando K3s en el nodo master..."

    # Obtener la dirección IP del nodo (debería ser la IP estática configurada)
    NODE_IP="${IP_ADDRESS%/*}"

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
    NODE_IP="${IP_ADDRESS%/*}"

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
