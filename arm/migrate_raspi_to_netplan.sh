#!/bin/bash

# Script orquestador para migrar Raspberry Pi de dhcpcd a netplan
# Se ejecuta EN LA LAPTOP y hace todo via SSH
# Uso: ./migrate_raspi_to_netplan.sh <IP_RASPI> [--yes] [INTERFACE] [RED_PARA_ESCANEAR]

# Parsear argumentos
AUTO_YES=false
ARGS=()
for arg in "$@"; do
    if [ "$arg" = "--yes" ] || [ "$arg" = "-y" ]; then
        AUTO_YES=true
    else
        ARGS+=("$arg")
    fi
done

RASPI_IP=${ARGS[0]}
INTERFACE=${ARGS[1]:-eth0}
NETWORK_SCAN=${ARGS[2]:-"192.168.4.0/22"}  # Usar /22 para cubrir rango completo
RASPI_USER="pi"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "Migración remota: dhcpcd → netplan"
echo "=========================================="
echo ""

# Validar parámetros
if [ -z "$RASPI_IP" ]; then
    echo "Uso: $0 <IP_RASPI> [--yes] [INTERFACE] [RED_PARA_ESCANEAR]"
    echo ""
    echo "Opciones:"
    echo "  --yes, -y    Responder automáticamente 'sí' a todas las confirmaciones"
    echo ""
    echo "Ejemplos:"
    echo "  $0 192.168.4.99"
    echo "  $0 192.168.4.99 --yes"
    echo "  $0 192.168.4.99 --yes eth0 192.168.4.0/24"
    exit 1
fi

echo "Raspberry Pi:    $RASPI_IP"
echo "Interface:       $INTERFACE"
echo "Red a escanear:  $NETWORK_SCAN"
echo "Usuario SSH:     $RASPI_USER"
echo ""

# Función para ejecutar comando remoto
ssh_exec() {
    ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$RASPI_USER@$RASPI_IP" "$@"
}

# Paso 0: Validar conexión SSH y reparar dpkg si es necesario
echo -e "${YELLOW}[0/10] Validando conexión SSH...${NC}"
if ! ssh_exec "echo 'SSH OK'" >/dev/null 2>&1; then
    echo -e "${RED}✗ No se puede conectar via SSH a $RASPI_IP${NC}"
    echo "Verifique:"
    echo "  - La IP es correcta"
    echo "  - El servicio SSH está activo"
    echo "  - Tiene permisos de acceso (clave SSH configurada)"
    exit 1
fi
echo -e "${GREEN}✓ Conexión SSH establecida${NC}"

# Verificar y reparar dpkg si está interrumpido
echo ""
echo -e "${YELLOW}[0.5/10] Verificando estado de dpkg...${NC}"
if ssh_exec "sudo dpkg --audit" 2>&1 | grep -q "is not properly installed"; then
    echo "  Reparando dpkg interrumpido..."
    ssh_exec "sudo dpkg --configure -a" >/dev/null 2>&1
    echo -e "${GREEN}  ✓ dpkg reparado${NC}"
else
    echo -e "${GREEN}  ✓ dpkg en buen estado${NC}"
fi

# Obtener información actual
CURRENT_HOSTNAME=$(ssh_exec "hostname")
CURRENT_IP=$(ssh_exec "ip addr show $INTERFACE | grep 'inet ' | awk '{print \$2}' | cut -d'/' -f1")
CURRENT_GATEWAY=$(ssh_exec "ip route | grep default | grep $INTERFACE | awk '{print \$3}' | head -n1")

echo ""
echo "Información actual del Raspberry Pi:"
echo "  Hostname:  $CURRENT_HOSTNAME"
echo "  IP:        $CURRENT_IP"
echo "  Gateway:   $CURRENT_GATEWAY"
echo ""

# Confirmar
if [ "$AUTO_YES" = false ]; then
    read -p "¿Continuar con la migración? (s/n): " confirm
    if [ "$confirm" != "s" ] && [ "$confirm" != "S" ]; then
        echo "Migración cancelada"
        exit 0
    fi
else
    echo "Modo automático: continuando con la migración..."
fi
echo ""

# Paso 1: Crear backup
echo ""
echo -e "${YELLOW}[1/10] Creando backup remoto...${NC}"
BACKUP_DIR="/root/network_backup_$(date +%Y%m%d_%H%M%S)"
ssh_exec "sudo mkdir -p $BACKUP_DIR"

# Backup dhcpcd.conf
if ssh_exec "test -f /etc/dhcpcd.conf"; then
    ssh_exec "sudo cp /etc/dhcpcd.conf $BACKUP_DIR/dhcpcd.conf.backup"
    echo -e "${GREEN}  ✓ Backup: dhcpcd.conf${NC}"
fi

# Backup netplan
if ssh_exec "test -d /etc/netplan"; then
    ssh_exec "sudo cp -r /etc/netplan $BACKUP_DIR/netplan.backup"
    echo -e "${GREEN}  ✓ Backup: /etc/netplan/${NC}"
fi

# Guardar estado de red
ssh_exec "ip addr show > /tmp/ip_addr.txt && sudo mv /tmp/ip_addr.txt $BACKUP_DIR/"
ssh_exec "ip route > /tmp/ip_route.txt && sudo mv /tmp/ip_route.txt $BACKUP_DIR/"
echo -e "${GREEN}  ✓ Estado de red guardado en: $BACKUP_DIR${NC}"

# Paso 2: Instalar netplan
echo ""
echo -e "${YELLOW}[2/10] Instalando netplan.io...${NC}"
if ! ssh_exec "command -v netplan >/dev/null 2>&1"; then
    echo "  Actualizando repositorios..."
    ssh_exec "sudo apt-get update -qq"
    echo "  Instalando netplan.io..."
    ssh_exec "sudo apt-get install -y netplan.io"
    echo -e "${GREEN}  ✓ netplan.io instalado${NC}"
else
    echo -e "${GREEN}  ✓ netplan ya está instalado${NC}"
fi

# Paso 3: Habilitar systemd-networkd
echo ""
echo -e "${YELLOW}[3/10] Habilitando systemd-networkd...${NC}"
ssh_exec "sudo systemctl enable systemd-networkd"
echo -e "${GREEN}  ✓ systemd-networkd habilitado${NC}"

# Paso 4: Limpiar configuraciones netplan previas
echo ""
echo -e "${YELLOW}[4/10] Limpiando configuraciones netplan previas...${NC}"
ssh_exec "sudo bash -c 'shopt -s nullglob; for file in /etc/netplan/*.yaml; do mv \"\$file\" \"\${file}.disabled\" && echo \"  - Deshabilitado: \$(basename \$file)\"; done'" || echo "  (No hay archivos previos)"

# Paso 5: Crear configuración netplan DHCP
echo ""
echo -e "${YELLOW}[5/10] Creando configuración netplan (DHCP)...${NC}"

# Crear el contenido del archivo localmente y enviarlo
cat > /tmp/netplan-config.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE:
      dhcp4: true
      dhcp6: false
      dhcp4-overrides:
        use-dns: true
        use-routes: true
EOF

# Copiar al Raspberry Pi
scp -o StrictHostKeyChecking=no /tmp/netplan-config.yaml "$RASPI_USER@$RASPI_IP:/tmp/" >/dev/null 2>&1
ssh_exec "sudo mv /tmp/netplan-config.yaml /etc/netplan/01-netplan-dhcp.yaml"
ssh_exec "sudo chmod 600 /etc/netplan/01-netplan-dhcp.yaml"
rm /tmp/netplan-config.yaml

echo -e "${GREEN}  ✓ Configuración netplan creada${NC}"

# Validar sintaxis
echo "  Validando sintaxis netplan..."
if ! ssh_exec "sudo netplan generate 2>/dev/null"; then
    echo -e "${RED}  ✗ Error en sintaxis netplan${NC}"
    exit 1
fi
echo -e "${GREEN}  ✓ Sintaxis válida${NC}"

# Paso 6: Aplicar netplan
echo ""
echo -e "${YELLOW}[6/10] Aplicando configuración netplan...${NC}"
echo -e "${YELLOW}  NOTA: La conexión SSH puede interrumpirse momentáneamente${NC}"
sleep 2

ssh_exec "sudo netplan apply" || true
sleep 3

echo "  Esperando a que la interfaz obtenga IP..."
max_retries=30
retry=0
while [ $retry -lt $max_retries ]; do
    if ssh_exec "ip addr show $INTERFACE | grep 'inet '" >/dev/null 2>&1; then
        NEW_IP=$(ssh_exec "ip addr show $INTERFACE | grep 'inet ' | awk '{print \$2}' | cut -d'/' -f1" 2>/dev/null || echo "")
        if [ -n "$NEW_IP" ] && [ "$NEW_IP" != "127.0.0.1" ]; then
            echo -e "${GREEN}  ✓ IP obtenida: $NEW_IP${NC}"
            break
        fi
    fi
    sleep 1
    retry=$((retry + 1))
done

if [ $retry -eq $max_retries ]; then
    echo -e "${YELLOW}  ⚠ Timeout esperando IP. Continuando...${NC}"
fi

# Paso 7: Configurar systemd-resolved
echo ""
echo -e "${YELLOW}[7/10] Configurando systemd-resolved...${NC}"
ssh_exec "sudo systemctl enable systemd-resolved"
ssh_exec "sudo systemctl start systemd-resolved"
echo -e "${GREEN}  ✓ systemd-resolved activo${NC}"

# Deshabilitar systemd-networkd-wait-online
ssh_exec "sudo systemctl disable systemd-networkd-wait-online.service 2>/dev/null || true"
ssh_exec "sudo systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true"
echo -e "${GREEN}  ✓ systemd-networkd-wait-online deshabilitado${NC}"

# Paso 8: Deshabilitar dhcpcd y NetworkManager
echo ""
echo -e "${YELLOW}[8/10] Deshabilitando servicios conflictivos...${NC}"

# Deshabilitar dhcpcd
if ssh_exec "systemctl is-active --quiet dhcpcd 2>/dev/null"; then
    ssh_exec "sudo systemctl stop dhcpcd"
    echo -e "${GREEN}  ✓ dhcpcd detenido${NC}"
fi

if ssh_exec "systemctl is-enabled --quiet dhcpcd 2>/dev/null"; then
    ssh_exec "sudo systemctl disable dhcpcd"
    echo -e "${GREEN}  ✓ dhcpcd deshabilitado${NC}"
fi

# Preguntar si desinstalar dhcpcd5
if [ "$AUTO_YES" = false ]; then
    read -p "¿Desinstalar dhcpcd5? (s/n): " remove_dhcpcd
else
    remove_dhcpcd="s"
    echo "  Modo automático: desinstalando dhcpcd5..."
fi

if [ "$remove_dhcpcd" = "s" ] || [ "$remove_dhcpcd" = "S" ]; then
    ssh_exec "sudo apt-get remove -y dhcpcd5"
    echo -e "${GREEN}  ✓ dhcpcd5 desinstalado${NC}"
else
    echo "  dhcpcd5 no desinstalado (solo deshabilitado)"
fi

# Deshabilitar NetworkManager si existe
if ssh_exec "systemctl is-enabled --quiet NetworkManager 2>/dev/null"; then
    ssh_exec "sudo systemctl disable NetworkManager"
    echo -e "${GREEN}  ✓ NetworkManager deshabilitado${NC}"
fi

# Paso 9: Reiniciar
echo ""
echo -e "${YELLOW}[9/10] Preparando reinicio...${NC}"
echo ""
echo "=========================================="
echo "RESUMEN:"
echo "=========================================="
echo "Hostname:        $CURRENT_HOSTNAME"
echo "IP original:     $CURRENT_IP"
echo "Gateway:         $CURRENT_GATEWAY"
echo "Backup en:       $BACKUP_DIR"
echo ""
echo "Configuración aplicada:"
echo "  - netplan.io:        ✓"
echo "  - systemd-networkd:  ✓"
echo "  - DHCP:              ✓"
echo "  - dhcpcd:            ✗ (deshabilitado)"
echo ""
echo "=========================================="
echo -e "${YELLOW}IMPORTANTE:${NC}"
echo "=========================================="
echo "1. El sistema se reiniciará"
echo "2. La IP puede cambiar (DHCP)"
echo "3. Después del reinicio, buscaremos la nueva IP"
echo ""

if [ "$AUTO_YES" = false ]; then
    read -p "¿Reiniciar el Raspberry Pi ahora? (s/n): " do_reboot
else
    do_reboot="s"
    echo "Modo automático: reiniciando..."
fi

if [ "$do_reboot" != "s" ] && [ "$do_reboot" != "S" ]; then
    echo ""
    echo "Migración completada sin reiniciar"
    echo "Ejecute manualmente: ssh $RASPI_USER@$RASPI_IP 'sudo reboot'"
    exit 0
fi

echo ""
echo -e "${YELLOW}Reiniciando Raspberry Pi...${NC}"
ssh_exec "sudo reboot" || true

echo ""
echo "=========================================="
echo "BUSCANDO NUEVA IP DESPUÉS DEL REINICIO"
echo "=========================================="
echo ""
echo "Esperando 45 segundos para que el sistema reinicie y SSH esté listo..."
sleep 45

echo "Escaneando red $NETWORK_SCAN con nmap..."
echo ""

# Escanear red con nmap (rápido)
FOUND_IPS=()
echo "Buscando hosts activos..."

# Primero hacer ping scan con nmap
echo "  Fase 1: Descubriendo hosts con nmap..."
ACTIVE_HOSTS=$(nmap -sn "$NETWORK_SCAN" -oG - 2>/dev/null | grep "Host:" | awk '{print $2}')
HOST_COUNT=$(echo "$ACTIVE_HOSTS" | wc -l)
echo "  → Encontrados $HOST_COUNT hosts activos"

# Esperar un poco más para que SSH esté completamente listo
echo "  Fase 2: Esperando que SSH esté listo (5 seg)..."
sleep 5

echo "  Fase 3: Verificando conectividad SSH..."
while IFS= read -r ip; do
    [ -z "$ip" ] && continue

    # Verificar si el puerto SSH está abierto
    if timeout 2 bash -c "echo >/dev/tcp/$ip/22" 2>/dev/null; then
        echo "    → Host con SSH: $ip"

        # Intentar obtener hostname (sin BatchMode para soportar password)
        REMOTE_HOST=$(timeout 5 ssh -o ConnectTimeout=3 -o StrictHostKeyChecking=no "$RASPI_USER@$ip" "hostname" 2>/dev/null || echo "unknown")

        if [ "$REMOTE_HOST" = "$CURRENT_HOSTNAME" ]; then
            echo -e "${GREEN}    ✓ ENCONTRADO: $ip - $REMOTE_HOST (¡MATCH!)${NC}"
            FOUND_IPS+=("$ip|$REMOTE_HOST|MATCH")
        elif [ "$REMOTE_HOST" != "unknown" ]; then
            echo "      Hostname: $REMOTE_HOST"
            FOUND_IPS+=("$ip|$REMOTE_HOST|OTHER")
        fi
    fi
done <<< "$ACTIVE_HOSTS"

echo ""
echo "=========================================="
echo "RESULTADOS:"
echo "=========================================="

if [ ${#FOUND_IPS[@]} -eq 0 ]; then
    echo -e "${RED}No se encontró el Raspberry Pi en la red${NC}"
    echo ""
    echo "Posibles causas:"
    echo "  - El sistema aún está reiniciando"
    echo "  - La red escaneada no es correcta"
    echo "  - El DHCP asignó una IP fuera del rango"
    echo ""
    echo "Intente nuevamente en 1-2 minutos"
    exit 1
fi

for item in "${FOUND_IPS[@]}"; do
    IP=$(echo "$item" | cut -d'|' -f1)
    HOSTNAME=$(echo "$item" | cut -d'|' -f2)
    STATUS=$(echo "$item" | cut -d'|' -f3)

    if [ "$STATUS" = "MATCH" ]; then
        echo -e "${GREEN}Nueva IP del Raspberry Pi: $IP${NC}"
        echo ""
        echo "Conectar:"
        echo "  ssh $RASPI_USER@$IP"
        echo ""
        echo "Verificar configuración:"
        echo "  ssh $RASPI_USER@$IP 'ip addr && ip route && systemctl status systemd-networkd'"
        NEW_RASPI_IP=$IP
    fi
done

echo ""
echo "=========================================="
echo -e "${YELLOW}[10/10] Limpieza final...${NC}"
echo "=========================================="

# Limpiar known_hosts para la IP antigua (evitar conflictos)
if [ -f ~/.ssh/known_hosts ]; then
    ssh-keygen -R "$RASPI_IP" 2>/dev/null || true
    if [ -n "$NEW_RASPI_IP" ] && [ "$NEW_RASPI_IP" != "$RASPI_IP" ]; then
        echo -e "${GREEN}  ✓ Entrada antigua removida de known_hosts${NC}"
    fi
fi

echo ""
echo "=========================================="
echo -e "${GREEN}MIGRACIÓN COMPLETADA EXITOSAMENTE${NC}"
echo "=========================================="

if [ -n "$NEW_RASPI_IP" ]; then
    echo ""
    echo "Comandos útiles:"
    echo "  ssh $RASPI_USER@$NEW_RASPI_IP"
    echo "  ssh $RASPI_USER@$NEW_RASPI_IP 'sudo cat /etc/netplan/*.yaml'"
    echo "  ssh $RASPI_USER@$NEW_RASPI_IP 'systemctl status systemd-networkd'"
fi

exit 0
