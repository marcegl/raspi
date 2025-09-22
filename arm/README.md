K3s Deployment Script for Raspberry Pi 4 Cluster
Automate the setup and optimization of a Kubernetes cluster using K3s on Raspberry Pi 4 devices running a clean installation of Raspberry Pi OS Lite 64-bit.

## Table of Contents

- [Table of Contents](#table-of-contents)
- [Introduction](#introduction)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Script Overview](#script-overview)
- [Usage](#usage)
  - [Before You Begin](#before-you-begin)
  - [Script Execution](#script-execution)
- [Parameters](#parameters)
  - [`setup_pre_reboot.sh`](#setup_pre_rebootsh)
  - [`setup_post_reboot.sh`](#setup_post_rebootsh)
- [Examples](#examples)
  - [Master Node Setup](#master-node-setup)
  - [Worker Node Setup](#worker-node-setup)
- [Notes](#notes)
- [Contributing](#contributing)
- [License](#license)

## Introduction

This script automates the configuration of Raspberry Pi 4 devices to form a K3s cluster. It includes system optimizations, static IP configuration, swap disabling, cgroup settings, security enhancements with Fail2ban, and performance tuning.

## Features

- Configures static IP addresses using dhcpcd.
- Sets hostnames without requiring a reboot.
- Disables swap for Kubernetes compatibility.
- Configures cgroup parameters required by K3s.
- Installs and configures Fail2ban for SSH protection.
- Applies system performance optimizations.
- Installs K3s master or worker nodes based on the role.
- Sets up kubectl for easy cluster management on the master node.

## Prerequisites

- Raspberry Pi 4 devices with Raspberry Pi OS Lite 64-bit (clean installation).
- SSH access to each Raspberry Pi.
- Basic knowledge of networking and Linux command-line operations.
- Static IP addresses planned for each Raspberry Pi.

## Script Overview

The deployment involves two scripts:

1. `setup_pre_reboot.sh`: Prepares the system by configuring the network, disabling swap, setting cgroup parameters, and applying system optimizations. The system reboots after running this script.
2. `setup_post_reboot.sh`: Installs K3s on the device after rebooting, setting it up as either a master or worker node.

## Usage

### Before You Begin

1. **Assign Static IP Addresses**: Decide on the static IP addresses for each Raspberry Pi. Ensure they are within the same subnet and do not conflict with other devices.
2. **Network Configuration**: Ensure your network allows for static IP assignment and that the gateway and DNS settings are correct.
3. **Obtain Master Node Token**: When setting up worker nodes, you’ll need the `NODE_TOKEN` from the master node.

### Script Execution

1. **Clone the Repository**

      ```sh
      git clone https://github.com/yourusername/your-repo-name.git
      cd your-repo-name
      ```

2. **Make Scripts Executable**

      ```sh
      chmod +x setup_pre_reboot.sh
      chmod +x setup_post_reboot.sh
      ```

3. **Run `setup_pre_reboot.sh`**

      For Master Node:

      ```sh
      ./setup_pre_reboot.sh master <IP_ADDRESS/CIDR> <GATEWAY> <HOSTNAME>
      ```

      For Worker Nodes:

      ```sh
      ./setup_pre_reboot.sh worker <IP_ADDRESS/CIDR> <GATEWAY> <HOSTNAME>
      ```

      The script will:

      - Update the system packages.
      - Configure the hostname.
      - Install dhcpcd and set a static IP.
      - Disable swap.
      - Configure cgroup parameters.
      - Install and configure Fail2ban.
      - Apply system performance optimizations.
      - Reboot the system.

4. **After Reboot, Run `setup_post_reboot.sh`**

      For Master Node:

      ```sh
      ./setup_post_reboot.sh master <IP_ADDRESS/CIDR> <HOSTNAME>
      ```

      For Worker Nodes:

      ```sh
      ./setup_post_reboot.sh worker <IP_ADDRESS/CIDR> <HOSTNAME> <MASTER_IP> <NODE_TOKEN>
      ```

      The script will:

      - Install K3s based on the specified role.
      - Configure kubectl on the master node for cluster management.
      - Display the status of K3s services.

## Parameters

### `setup_pre_reboot.sh`

- `<ROLE>`: Role of the node (master or worker).
- `<IP_ADDRESS/CIDR>`: Static IP address with CIDR notation (e.g., 192.168.1.85/24).
- `<GATEWAY>`: Gateway IP address (e.g., 192.168.1.254).
- `<HOSTNAME>`: Desired hostname for the Raspberry Pi.

### `setup_post_reboot.sh`

- `<ROLE>`: Role of the node (master or worker).
- `<IP_ADDRESS/CIDR>`: Static IP address with CIDR notation.
- `<HOSTNAME>`: Hostname set previously.
- `<MASTER_IP>`: (Workers only) IP address of the master node.
- `<NODE_TOKEN>`: (Workers only) Node token obtained from the master node.

## Examples

### Master Node Setup

**Pre-Reboot Script:**

```sh
./setup_pre_reboot.sh master 192.168.1.85/24 192.168.1.254 pi-master
```

**Post-Reboot Script:**

```sh
./setup_post_reboot.sh master 192.168.1.85/24 pi-master
```

### Worker Node Setup

**Pre-Reboot Script:**

```sh
./setup_pre_reboot.sh worker 192.168.1.86/24 192.168.1.254 pi-worker-1
```

**Post-Reboot Script:**

Obtain the `NODE_TOKEN` from the master node:

```sh
sudo cat /var/lib/rancher/k3s/server/node-token
```

Then run:

```sh
./setup_post_reboot.sh worker 192.168.1.86/24 pi-worker-1 192.168.1.85 <NODE_TOKEN>
```

## Notes

- **Permissions**: Ensure that the user executing the scripts has sudo privileges.
- **Swap Disable**: Disabling swap is necessary for Kubernetes to manage resources effectively.
- **Cgroup Parameters**: The cgroup settings are crucial for K3s to function correctly on Raspberry Pi.
- **Fail2ban**: Provides basic security by protecting against SSH brute-force attacks.
- **Network Manager Conflicts**: Installing dhcpcd on systems using other network managers may cause conflicts.

## Contributing

Contributions are welcome! Please open an issue or submit a pull request for any improvements or bug fixes.

1. Fork the repository.
2. Create a new branch: `git checkout -b feature/your-feature`.
3. Commit your changes: `git commit -am 'Add new feature'`.
4. Push to the branch: `git push origin feature/your-feature`.
5. Open a pull request.

## License

This project is licensed under the AGPL-3.0 License. See the LICENSE file for details.

_Disclaimer: This script is provided as-is without any guarantees. Use it at your own risk._