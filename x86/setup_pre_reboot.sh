#!/bin/bash

# Parámetros esperados
IP_ADDRESS=$1      # Dirección IP estática, por ejemplo, '192.168.1.85/24'
GATEWAY=$2         # Dirección IP del gateway, por ejemplo, '192.168.1.254'
HOSTNAME=$3        # Hostname para Ubuntu Server
INTERFACE=${4:-$(ip route | grep default | awk '{print $5}' | head -n1)}  # Interface de red (autodetectada si no se especifica)

# Verificar que se proporcionaron los parámetros necesarios
if [ -z "$IP_ADDRESS" ] || [ -z "$GATEWAY" ] || [ -z "$HOSTNAME" ]; then
    echo "Uso: $0 <IP_ADDRESS/CIDR> <GATEWAY> <HOSTNAME> [INTERFACE]"
    echo "Ejemplo: $0 192.168.1.85/24 192.168.1.254 ubuntu-master"
    exit 1
fi

# Validar que el gateway esté en la misma red que la IP
IP_NET=$(echo $IP_ADDRESS | cut -d'/' -f1 | cut -d'.' -f1-3)
GW_NET=$(echo $GATEWAY | cut -d'.' -f1-3)
if [ "$IP_NET" != "$GW_NET" ]; then
    echo "ADVERTENCIA: El gateway $GATEWAY no está en la misma red que la IP $IP_ADDRESS"
    echo "¿Desea continuar de todas formas? (s/n)"
    read -r respuesta
    if [ "$respuesta" != "s" ] && [ "$respuesta" != "S" ]; then
        exit 1
    fi
fi

# Verificar que es Ubuntu Server
if ! grep -q "Ubuntu" /etc/os-release; then
    echo "Este script está diseñado para Ubuntu Server 24.04"
    exit 1
fi

# Asegurarse de que el sistema esté actualizado
sudo apt-get update && sudo apt-get upgrade -y

# Configurar el hostname sin reiniciar
sudo hostnamectl set-hostname "$HOSTNAME"
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $HOSTNAME/g" /etc/hosts
echo "Hostname configurado en: $HOSTNAME"

# Deshabilitar cloud-init networking si existe
if [ -d /etc/cloud ]; then
    sudo mkdir -p /etc/cloud/cloud.cfg.d
    echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
    echo "Cloud-init networking deshabilitado."
fi

# Eliminar configuraciones netplan previas que puedan causar conflictos
echo "Limpiando configuraciones netplan previas..."
if [ -f /etc/netplan/50-cloud-init.yaml ]; then
    sudo mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.disabled
    echo "  - Deshabilitado: 50-cloud-init.yaml"
fi
if [ -f /etc/netplan/00-installer-config.yaml ]; then
    sudo mv /etc/netplan/00-installer-config.yaml /etc/netplan/00-installer-config.yaml.disabled
    echo "  - Deshabilitado: 00-installer-config.yaml"
fi
# Buscar otros archivos yaml que puedan interferir
for file in /etc/netplan/*.yaml; do
    if [ -f "$file" ] && [ "$file" != "$NETPLAN_FILE" ]; then
        sudo mv "$file" "${file}.disabled"
        echo "  - Deshabilitado: $(basename $file)"
    fi
done

# Configurar IP estática usando netplan
NETPLAN_FILE="/etc/netplan/01-k3s-config.yaml"
sudo bash -c "cat > $NETPLAN_FILE <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: false
      dhcp6: false
      addresses:
        - $IP_ADDRESS
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$GATEWAY, 8.8.8.8, 8.8.4.4]
EOF"

# Establecer permisos correctos para el archivo netplan
sudo chmod 600 $NETPLAN_FILE
echo "Permisos de archivo netplan configurados correctamente."

# Validar y aplicar configuración de netplan
sudo netplan try --timeout=30
if [ $? -eq 0 ]; then
    sudo netplan apply
    echo "Configuración de IP estática aplicada con netplan."

    # Verificar que la configuración se aplicó correctamente
    sleep 3
    CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}')
    if echo "$CURRENT_IP" | grep -q "$(echo $IP_ADDRESS | cut -d'/' -f1)"; then
        echo "✓ IP configurada correctamente: $CURRENT_IP"
    else
        echo "⚠ ADVERTENCIA: La IP actual ($CURRENT_IP) no coincide con la configurada ($IP_ADDRESS)"
    fi

    # Verificar que no hay DHCP activo
    if networkctl status $INTERFACE 2>/dev/null | grep -q "DHCP4"; then
        echo "⚠ ADVERTENCIA: DHCP sigue activo en la interfaz. Verificando configuración..."
        # Intentar forzar la deshabilitación de DHCP
        sudo systemctl restart systemd-networkd
        sleep 2
    fi
else
    echo "Error en configuración netplan. Revise la sintaxis."
    exit 1
fi

# Deshabilitar swap completamente
sudo swapoff -a
sudo systemctl mask swap.target
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
echo "Swap deshabilitado permanentemente."

# Configurar parámetros del kernel para K3s
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1

# Configurar parámetros de rendimiento de red
sudo sysctl -w net.core.rmem_max=2500000
sudo sysctl -w net.core.wmem_max=2500000
sudo sysctl -w net.core.netdev_max_backlog=5000
sudo sysctl -w vm.swappiness=1

# Hacer permanentes los parámetros del kernel
sudo bash -c 'cat >> /etc/sysctl.conf <<EOF

# Configuración para K3s
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Optimizaciones de red para K3s
net.core.rmem_max = 2500000
net.core.wmem_max = 2500000
net.core.netdev_max_backlog = 5000
vm.swappiness = 1
EOF'

# Cargar módulo br_netfilter si no está cargado
if ! lsmod | grep -q br_netfilter; then
    sudo modprobe br_netfilter
    echo 'br_netfilter' | sudo tee /etc/modules-load.d/k3s.conf
fi

# Instalar paquetes esenciales para K3s
sudo apt-get install -y curl iptables-persistent

# Instalar y configurar fail2ban
sudo apt-get install -y fail2ban
sudo bash -c 'cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 1h
findtime  = 10m
maxretry = 5

[sshd]
enabled = true
port    = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
EOF'

sudo systemctl enable fail2ban
sudo systemctl restart fail2ban
echo "Fail2ban instalado y configurado."

# Aplicar configuraciones de sysctl
sudo sysctl -p

# Configurar systemd-resolved para mejorar DNS
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved

# Optimizar sistema de archivos (noatime para mejor rendimiento)
sudo sed -i 's/\([[:space:]]\)defaults/\1defaults,noatime/' /etc/fstab
sudo sed -i 's/\([[:space:]]\)errors=remount-ro/\1noatime,errors=remount-ro/' /etc/fstab
echo "Parámetros de rendimiento configurados."

# Deshabilitar systemd-networkd-wait-online para evitar retrasos en el arranque
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
echo "Servicio de espera de red deshabilitado para arranque más rápido."

echo "Configuración pre-reboot completada. El sistema se reiniciará en 10 segundos..."
echo "Después del reinicio, ejecute setup_post_reboot.sh master o setup_post_reboot.sh worker <MASTER_IP> <TOKEN>"
sleep 10

# Reiniciar para aplicar cambios
sudo reboot