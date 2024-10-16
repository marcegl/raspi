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

# Instalar dhcpcd si no está instalado
if ! command -v dhcpcd >/dev/null 2>&1; then
    echo "Instalando dhcpcd..."
    sudo apt-get install -y dhcpcd5
    sudo systemctl enable dhcpcd
fi

# Configurar IP estática en /etc/dhcpcd.conf
sudo bash -c "cat >> /etc/dhcpcd.conf <<EOF

interface eth0
static ip_address=$IP_ADDRESS
static routers=$GATEWAY
static domain_name_servers=$GATEWAY 8.8.8.8
EOF"
echo "Configuración de IP estática aplicada en /etc/dhcpcd.conf."

# Reiniciar el servicio dhcpcd para aplicar cambios
sudo systemctl restart dhcpcd
echo "Servicio dhcpcd reiniciado."

# Esperar a que la interfaz de red esté activa con la nueva IP
echo "Esperando a que la interfaz eth0 tenga la nueva IP..."
until ip addr show eth0 | grep -q "${IP_ADDRESS%/*}"; do
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
exit 0
