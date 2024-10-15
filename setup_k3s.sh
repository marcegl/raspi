#!/bin/bash

# Parámetros esperados
ROLE=$1  # 'master' o 'worker'
IP_SUFFIX=$2  # Por ejemplo, '201' para 192.168.123.201
MASTER_SUFFIX=${3:-"201"}  # Sufijo de la IP del nodo master, por defecto 201
NODE_TOKEN=$4  # Token del nodo master (obligatorio para workers)
HOSTNAME=$5  # Hostname para el Raspberry Pi

# Configurar el hostname
sudo hostnamectl set-hostname $HOSTNAME

# Actualizar /etc/hosts
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $HOSTNAME/g" /etc/hosts

# Configuración de IP fija
sudo bash -c "cat <<EOF >> /etc/dhcpcd.conf
interface eth0
static ip_address=192.168.123.${IP_SUFFIX}/24
static routers=192.168.123.1
static domain_name_servers=192.168.123.1 8.8.8.8
EOF"

# Reiniciar el servicio de red para aplicar la nueva IP
sudo systemctl restart dhcpcd

# Verificar la IP asignada
IP_ASSIGNED=$(hostname -I | awk '{print $1}')
echo "IP asignada: $IP_ASSIGNED"

# Configuración de cgroups (necesaria para K3s)
sudo sed -i 's/$/ cgroup_memory=1 cgroup_enable=memory/' /boot/cmdline.txt

# Instalar fail2ban para mejorar la seguridad
sudo apt-get update
sudo apt-get install -y fail2ban

# Configurar fail2ban (se puede personalizar según sea necesario)
sudo bash -c "cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime  = 10m
maxretry = 5
destemail = root@localhost
sender = root@$(hostname -f)
mta = sendmail
action = %(action_mwl)s

[sshd]
enabled = true
EOF"

# Reiniciar fail2ban para aplicar la configuración
sudo systemctl restart fail2ban

# Detectar si es el nodo master o worker
if [ "$ROLE" == "master" ]; then
    echo "Instalando K3s en el nodo master..."
    
    # Instalar K3s en el nodo master
    curl -sfL https://get.k3s.io | sh -s - server --write-kubeconfig-mode 644 --node-name "$(hostname)"

    # Obtener el token para los nodos worker y mostrarlo
    NODE_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/node-token)
    echo "Token del nodo master: $NODE_TOKEN"
    echo "Guarda este token para usarlo en la configuración de los nodos worker."

else
    echo "Instalando K3s en un nodo worker..."
    
    if [ -z "$NODE_TOKEN" ]; then
        echo "Por favor, proporciona el NODE_TOKEN obtenido del nodo master."
        exit 1
    fi

    # Instalar K3s en el nodo worker usando el token
    curl -sfL https://get.k3s.io | K3S_URL="https://${MASTER_IP}:6443" K3S_TOKEN="${NODE_TOKEN}" sh -
fi

# Optimización: Habilitar el tráfico IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
sudo sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

# Deshabilitar el swap
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Optimización: Deshabilitar el controlador de sonido para liberar más memoria
sudo echo "dtparam=audio=off" | sudo tee -a /boot/config.txt

# Optimización de buffers de red
sudo sysctl -w net.core.rmem_max=2500000
sudo sysctl -w net.core.wmem_max=2500000
sudo sysctl -w net.core.netdev_max_backlog=5000

# Optimización del sistema de archivos para SD de alta performance
sudo tune2fs -o journal_data_writeback /dev/mmcblk0p2
sudo mount -o remount,noatime /dev/mmcblk0p2

# Comprobar el estado de K3s
sudo systemctl status k3s

echo "Instalación completada en $(hostname)"