#!/bin/bash

# Script para actualizar la IP de un nodo K3s vía SSH
# Ejecutar desde tu máquina local

ROLE=$1           # 'master' o 'worker'
NODE_IP=$2        # IP del nodo a actualizar
MASTER_IP=$3      # IP del master (solo para workers)
SSH_USER="pi"     # Cambiar si usas otro usuario

# Validar parámetros
if [ -z "$ROLE" ] || [ -z "$NODE_IP" ]; then
    echo "Uso:"
    echo "  Para master: $0 master <NODE_IP>"
    echo "  Para worker: $0 worker <NODE_IP> <MASTER_IP>"
    echo ""
    echo "Ejemplos:"
    echo "  $0 master 192.168.1.100"
    echo "  $0 worker 192.168.1.101 192.168.1.100"
    exit 1
fi

if [ "$ROLE" == "worker" ] && [ -z "$MASTER_IP" ]; then
    echo "Error: Para workers debes especificar la IP del master"
    echo "Uso: $0 worker <NODE_IP> <MASTER_IP>"
    exit 1
fi

echo "==================================================================="
echo "Actualizando nodo K3s vía SSH"
echo "==================================================================="
echo "Rol: $ROLE"
echo "IP del nodo: $NODE_IP"
if [ "$ROLE" == "worker" ]; then
    echo "IP del master: $MASTER_IP"
fi
echo "==================================================================="
echo ""

# Actualizar nodo master
if [ "$ROLE" == "master" ]; then
    echo ">>> Actualizando nodo MASTER..."

    echo "Deteniendo K3s..."
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl stop k3s"

    echo "Actualizando configuración..."
    ssh ${SSH_USER}@${NODE_IP} "sudo sed -i 's/--node-ip=[0-9.]*\b/--node-ip=$NODE_IP/g' /etc/systemd/system/k3s.service"
    ssh ${SSH_USER}@${NODE_IP} "sudo sed -i 's/--bind-address=[0-9.]*\b/--bind-address=$NODE_IP/g' /etc/systemd/system/k3s.service"
    ssh ${SSH_USER}@${NODE_IP} "sudo sed -i 's/--advertise-address=[0-9.]*\b/--advertise-address=$NODE_IP/g' /etc/systemd/system/k3s.service"
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl daemon-reload"

    echo "Iniciando K3s..."
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl start k3s"

    echo "Esperando a que K3s esté listo..."
    sleep 15

    echo ""
    echo "Estado del servicio K3s:"
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl status k3s --no-pager | head -10"

    echo ""
    echo "Nodos del cluster:"
    ssh ${SSH_USER}@${NODE_IP} "kubectl get nodes -o wide"

    echo ""
    echo "✓ Nodo master actualizado correctamente"

# Actualizar nodo worker
elif [ "$ROLE" == "worker" ]; then
    echo ">>> Actualizando nodo WORKER..."

    echo "Deteniendo K3s agent..."
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl stop k3s-agent"

    echo "Actualizando configuración..."
    ssh ${SSH_USER}@${NODE_IP} "sudo sed -i 's/--node-ip=[0-9.]*\b/--node-ip=$NODE_IP/g' /etc/systemd/system/k3s-agent.service"
    ssh ${SSH_USER}@${NODE_IP} "sudo sed -i 's|https://[0-9.]*:6443|https://$MASTER_IP:6443|g' /etc/systemd/system/k3s-agent.service"
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl daemon-reload"

    echo "Iniciando K3s agent..."
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl start k3s-agent"

    echo "Esperando a que K3s agent esté listo..."
    sleep 10

    echo ""
    echo "Estado del servicio K3s agent:"
    ssh ${SSH_USER}@${NODE_IP} "sudo systemctl status k3s-agent --no-pager | head -10"

    echo ""
    echo "✓ Nodo worker actualizado correctamente"
    echo ""
    echo "Verifica el estado del nodo desde el master con:"
    echo "  ssh ${SSH_USER}@${MASTER_IP} 'kubectl get nodes -o wide'"

else
    echo "Error: Rol inválido '$ROLE'. Usa 'master' o 'worker'"
    exit 1
fi

echo ""
echo "==================================================================="
echo "Actualización completada"
echo "==================================================================="
