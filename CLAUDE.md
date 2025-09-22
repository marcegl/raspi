# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a K3s deployment automation project for Raspberry Pi 4 clusters. The repository contains shell scripts to automate the setup and optimization of Kubernetes clusters using K3s on Raspberry Pi devices running Raspberry Pi OS Lite 64-bit.

## Architecture

The deployment follows a two-phase approach:

1. **Pre-reboot setup** (`setup_pre_reboot.sh`): Configures system-level settings including networking, swap, cgroups, security, and performance optimizations
2. **Post-reboot setup** (`setup_post_reboot.sh`): Installs and configures K3s as either master or worker nodes

### Directory Structure

- `arm/`: Contains scripts specifically for ARM-based Raspberry Pi devices
  - `setup_pre_reboot.sh`: System preparation script
  - `setup_post_reboot.sh`: K3s installation script
  - `README.md`: Comprehensive documentation
- `x86/`: Directory for potential x86 implementations (currently empty)

## Common Commands

### Script Execution
```bash
# Make scripts executable
chmod +x arm/setup_pre_reboot.sh arm/setup_post_reboot.sh

# Master node setup (pre-reboot)
./arm/setup_pre_reboot.sh master <IP_ADDRESS/CIDR> <GATEWAY> <HOSTNAME>

# Master node setup (post-reboot)
./arm/setup_post_reboot.sh master <IP_ADDRESS/CIDR> <HOSTNAME>

# Worker node setup (pre-reboot)
./arm/setup_pre_reboot.sh worker <IP_ADDRESS/CIDR> <GATEWAY> <HOSTNAME>

# Worker node setup (post-reboot)
./arm/setup_post_reboot.sh worker <IP_ADDRESS/CIDR> <HOSTNAME> <MASTER_IP> <NODE_TOKEN>

# Get master node token
sudo cat /var/lib/rancher/k3s/server/node-token
```

### K3s Management
```bash
# Check cluster status
kubectl get nodes

# Check K3s service status (master)
sudo systemctl status k3s

# Check K3s agent status (worker)
sudo systemctl status k3s-agent
```

## Key Configuration Details

- **Static IP Configuration**: Uses dhcpcd for network configuration
- **Security**: Implements Fail2ban for SSH protection
- **Performance**: Disables audio, optimizes network buffers, enables noatime
- **Kubernetes Requirements**: Disables swap, configures cgroups, enables IP forwarding
- **K3s Configuration**: Disables Traefik and ServiceLB, uses custom node names and IPs

## Development Notes

- Scripts are written in Spanish (comments and echo messages)
- Target platform: Raspberry Pi 4 with Raspberry Pi OS Lite 64-bit
- K3s configuration files location: `/etc/rancher/k3s/`
- Kubectl config location: `~/.kube/config`
- Node token storage: `~/k3s-node-token.txt`

## Script Parameters

Both scripts expect specific parameters in order:
- `ROLE`: 'master' or 'worker'
- `IP_ADDRESS`: Static IP with CIDR notation (e.g., '192.168.1.85/24')
- `GATEWAY`: Gateway IP address
- `HOSTNAME`: Desired hostname for the Pi
- `MASTER_IP`: (Workers only) Master node IP
- `NODE_TOKEN`: (Workers only) Token from master node