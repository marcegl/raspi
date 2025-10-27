#!/bin/bash

# Parámetros esperados
IP_ADDRESS=$1      # Dirección IP estática, por ejemplo, '192.168.1.85/24'
GATEWAY=$2         # Dirección IP del gateway, por ejemplo, '192.168.1.254'
HOSTNAME=$3        # Hostname para el Raspberry Pi
INTERFACE=${4:-eth0}  # Interface de red (por defecto eth0 en Raspberry Pi)

# Verificar que se proporcionaron los parámetros necesarios
if [ -z "$IP_ADDRESS" ] || [ -z "$GATEWAY" ] || [ -z "$HOSTNAME" ]; then
    echo "Uso: $0 <IP_ADDRESS/CIDR> <GATEWAY> <HOSTNAME> [INTERFACE]"
    echo "Ejemplo: $0 192.168.1.85/24 192.168.1.254 raspi-master eth0"
    exit 1
fi

# Asegurarse de que el sistema esté actualizado
sudo apt-get update && sudo apt-get upgrade -y

# Configurar el hostname sin reiniciar
sudo hostnamectl set-hostname "$HOSTNAME"
sudo sed -i "s/127.0.1.1.*/127.0.1.1    $HOSTNAME/g" /etc/hosts
echo "Hostname configurado en: $HOSTNAME"

# Instalar netplan si no está instalado
if ! command -v netplan >/dev/null 2>&1; then
    echo "Instalando netplan.io..."
    sudo apt-get install -y netplan.io
fi

# Habilitar systemd-networkd
sudo systemctl enable systemd-networkd
echo "systemd-networkd habilitado."

# Limpiar configuraciones netplan previas (si existen de instalación previa)
echo "Limpiando configuraciones netplan previas..."
for file in /etc/netplan/*.yaml; do
    if [ -f "$file" ]; then
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
echo "Configuración netplan creada en: $NETPLAN_FILE"

# Validar y aplicar configuración de netplan
echo "Aplicando configuración netplan..."
sudo netplan generate
sudo netplan apply
echo "Configuración de IP estática aplicada con netplan."

# Verificar que la configuración se aplicó correctamente
sleep 3
CURRENT_IP=$(ip addr show $INTERFACE | grep "inet " | awk '{print $2}')
if echo "$CURRENT_IP" | grep -q "$(echo $IP_ADDRESS | cut -d'/' -f1)"; then
    echo "✓ IP configurada correctamente: $CURRENT_IP"
else
    echo "⚠ ADVERTENCIA: La IP actual ($CURRENT_IP) no coincide con la configurada ($IP_ADDRESS)"
    echo "Esto es normal si se aplicará después del reinicio."
fi

# AHORA que systemd-networkd está activo, deshabilitar NetworkManager
# NetworkManager viene por defecto en Raspberry Pi OS Bookworm y causa conflictos
if systemctl is-enabled --quiet NetworkManager 2>/dev/null; then
    echo "Deshabilitando NetworkManager (systemd-networkd ya está activo)..."
    sudo systemctl disable NetworkManager
    # Solo deshabilitar, no detener, para evitar interrupciones durante SSH
    # Se detendrá automáticamente en el próximo reinicio
    echo "NetworkManager deshabilitado. Se detendrá en el próximo reinicio."
fi

# Deshabilitar el uso de swapfile
sudo dphys-swapfile swapoff
sudo systemctl disable dphys-swapfile
echo "Swapfile deshabilitado."

# Configurar cgroups si no están configurados
CGROUP_PARAMS="cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory"
CMDLINE_FILE="/boot/firmware/cmdline.txt"

if ! grep -q "cgroup_enable" "$CMDLINE_FILE"; then
    sudo sed -i "s|$| $CGROUP_PARAMS|" "$CMDLINE_FILE"
    echo "Parámetros de cgroup añadidos a $CMDLINE_FILE"
else
    echo "Parámetros de cgroup ya están configurados en $CMDLINE_FILE"
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

# Configuración de parámetros del kernel para K3s
sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w vm.swappiness=1

# Hacer permanentes los parámetros del kernel
if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
fi

if ! grep -q "vm.swappiness = 1" /etc/sysctl.conf; then
    echo "vm.swappiness = 1" | sudo tee -a /etc/sysctl.conf
fi
echo "Parámetros del kernel configurados."

# Configuración de rendimiento
CONFIG_FILE="/boot/firmware/config.txt"

if ! grep -q "dtparam=audio=off" "$CONFIG_FILE"; then
    echo "dtparam=audio=off" | sudo tee -a "$CONFIG_FILE"
fi
sudo sed -i 's/errors=remount-ro/noatime,errors=remount-ro/' /etc/fstab
echo "Parámetros de rendimiento configurados."

# Instalar iptables para asegurar que K3s funcione correctamente
sudo apt-get install -y iptables

# Configurar systemd-resolved para mejorar DNS
sudo systemctl enable systemd-resolved
sudo systemctl start systemd-resolved

# Deshabilitar systemd-networkd-wait-online para evitar retrasos en el arranque
sudo systemctl disable systemd-networkd-wait-online.service
sudo systemctl mask systemd-networkd-wait-online.service
echo "Servicio de espera de red deshabilitado para arranque más rápido."

# Reiniciar para aplicar cambios de cgroups y otros
echo "Reiniciando el sistema para aplicar cambios..."
sudo reboot

# El script se detendrá aquí debido al reinicio
exit 0
