<p align="left">
  **EN** | <a href="README_RU.md">RU</a>
</p>
# Remnawave Manager v 0.5.6 ⚙️

This script is a multi-functional tool for **managing and configuring Remnawave and Remnanode components** on a server. It significantly simplifies the process of deploying a VPN server by automating routine tasks such as installing Docker, setting up backups, a firewall, and SSH.

> **Compatibility:** The script is currently compatible with **Ubuntu** and **Debian** operating systems.

### **Script Interface Preview**

![Script Preview](https://raw.githubusercontent.com/Hopper65S/Remnawave-autoinstall-script/main/preview.png)
---

### **💾 Key Features**

* **VPN Server Management:** Deploy and configure a full-featured VPN server using the Remnawave control panel and a Remnanode.
* **Automated Installation:** Automatic installation of necessary components, including repositories and Docker.
* **Server Security:** Enhanced security by creating a separate user and configuring SSH keys.
* **Network Configuration:** Firewall (iptables) setup, opening only the necessary ports.
* **Database Backup:** Creation of database and, if needed, full directory backups with the option to send them to Telegram.
* **Docker Management:** Management of Docker containers for both Remnawave and Remnanode.
* **WARP Support:** Ability to add Cloudflare's WARP for additional traffic proxying.
* **Multilingual Interface:** Supports both Russian and English for the menu and messages.

> **ATTENTION:** This script is still in development, and there may be some issues with its operation.
---

### **🚀 Installation**

To install and run the script on your server, use the following `curl` command:

```bash
curl -O [https://raw.githubusercontent.com/Hopper65S/Remnawave-autoinstall-script/main/setup_remnawave.sh](https://raw.githubusercontent.com/Hopper65S/Remnawave-autoinstall-script/main/setup_remnawave.sh) && chmod +x setup_remnawave.sh
