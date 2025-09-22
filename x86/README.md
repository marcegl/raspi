# K3s Deployment Script for Ubuntu Server 24.04

Scripts especializados para automatizar la configuración de clusters K3s en servidores Ubuntu Server 24.04 x86/x64.

## Características Específicas Ubuntu 24.04

- **Networking**: Configuración con Netplan (renderer: networkd)
- **Swap Management**: Deshabilitación completa usando systemd mask
- **Dependencies**: Paquetes mínimos optimizados para Ubuntu Server
- **Security**: Fail2ban con configuración específica para Ubuntu
- **Performance**: Optimizaciones de kernel y sistema de archivos

## Diferencias vs ARM/Raspberry Pi

| Aspecto | ARM/Raspberry Pi | x86/Ubuntu Server |
|---------|------------------|-------------------|
| Network Config | dhcpcd | netplan + networkd |
| Swap Disable | dphys-swapfile | systemctl mask + fstab |
| Boot Config | /boot/firmware/ | /etc/sysctl.conf |
| Package Manager | apt (Raspberry Pi OS) | apt (Ubuntu Server) |
| Cgroups | cmdline.txt | systemd nativo |

## Uso

### Script Pre-Reboot
```bash
chmod +x setup_pre_reboot.sh
./setup_pre_reboot.sh master 192.168.1.100/24 192.168.1.1 ubuntu-master
```

### Script Post-Reboot
```bash
# Master
./setup_post_reboot.sh master 192.168.1.100/24 ubuntu-master

# Worker
./setup_post_reboot.sh worker 192.168.1.101/24 ubuntu-worker-1 192.168.1.100 <NODE_TOKEN>
```

## Parámetros

### setup_pre_reboot.sh
- `<ROLE>`: master o worker
- `<IP_ADDRESS/CIDR>`: IP estática con notación CIDR
- `<GATEWAY>`: IP del gateway
- `<HOSTNAME>`: Hostname del servidor
- `[INTERFACE]`: Interfaz de red (autodetectada si se omite)

### setup_post_reboot.sh
- Master: `<ROLE> <IP_ADDRESS/CIDR> <HOSTNAME>`
- Worker: `<ROLE> <IP_ADDRESS/CIDR> <HOSTNAME> <MASTER_IP> <NODE_TOKEN>`

## Verificaciones

```bash
# Estado del cluster
kubectl get nodes -o wide

# Logs del servicio
sudo journalctl -u k3s -f

# Estado de networking
sudo netplan status
```

## Requisitos del Sistema

- Ubuntu Server 24.04 LTS
- Acceso a internet para descargar K3s
- Privilegios sudo
- Mínimo 1GB RAM por nodo
- Red configurada con IPs estáticas planificadas