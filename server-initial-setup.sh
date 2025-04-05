#!/bin/bash

# Script setup awal untuk Ubuntu 22.04
# Menginstal Docker, Docker Compose, dan mengaktifkan firewall

# Memastikan script dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    echo "Script ini harus dijalankan sebagai root atau dengan sudo"
    exit 1
fi

echo "======================================================"
echo "  Setup Awal Server Ubuntu 22.04"
echo "  - Instalasi Docker"
echo "  - Instalasi Docker Compose"
echo "  - Konfigurasi Firewall"
echo "======================================================"

# Update sistem
echo "[1/7] Memperbarui paket sistem..."
apt update && apt upgrade -y

# Instalasi paket yang diperlukan
echo "[2/7] Menginstal paket yang diperlukan..."
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release ufw

# Menambahkan Docker repository
echo "[3/7] Menambahkan Docker repository..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update

# Instalasi Docker Engine
echo "[4/7] Menginstal Docker Engine..."
apt install -y docker-ce docker-ce-cli containerd.io

# Menambahkan pengguna saat ini ke grup docker (jika tidak root)
if [ "$SUDO_USER" ]; then
    echo "[5/7] Menambahkan pengguna $SUDO_USER ke grup docker..."
    usermod -aG docker $SUDO_USER
    echo "Pengguna $SUDO_USER ditambahkan ke grup docker. Log out dan log in kembali untuk menggunakan Docker tanpa sudo."
fi

# Instalasi Docker Compose
echo "[6/7] Menginstal Docker Compose..."
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Konfigurasi Firewall (UFW)
echo "[7/7] Mengkonfigurasi Firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# Memeriksa status instalasi
echo "======================================================"
echo "Verifikasi Instalasi:"
echo "--------------------"
echo "Docker Version:"
docker --version
echo "--------------------"
echo "Docker Compose Version:"
docker-compose --version
echo "--------------------"
echo "Firewall Status:"
ufw status verbose
echo "======================================================"

echo "Setup selesai! Server Anda telah dikonfigurasi dengan Docker, Docker Compose, dan Firewall."
echo "Docker daemon sudah berjalan dan dimulai secara otomatis saat boot."
echo "Firewall telah diaktifkan dengan port SSH, HTTP, dan HTTPS terbuka."