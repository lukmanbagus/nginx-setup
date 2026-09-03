#!/bin/bash

# Script setup awal untuk Ubuntu 22.04 / 24.04 / 26.04
# Menginstal Docker, Docker Compose, mengaktifkan firewall,
# mengamankan SSH, dan mengaktifkan fail2ban

set -e

# Memastikan script dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    echo "Script ini harus dijalankan sebagai root atau dengan sudo"
    exit 1
fi

echo "======================================================"
echo "  Setup Awal Server Ubuntu"
echo "  - Instalasi Docker"
echo "  - Instalasi Docker Compose"
echo "  - Konfigurasi Firewall (UFW)"
echo "  - Hardening SSH (disable password auth)"
echo "  - Instalasi & aktivasi Fail2ban"
echo "======================================================"

# Deteksi versi Ubuntu
UBUNTU_CODENAME=$(lsb_release -cs)
UBUNTU_VERSION=$(lsb_release -rs)
echo "Terdeteksi Ubuntu ${UBUNTU_VERSION} (${UBUNTU_CODENAME})"

SUPPORTED_VERSIONS=("22.04" "24.04" "26.04")
IS_SUPPORTED=false
for v in "${SUPPORTED_VERSIONS[@]}"; do
    if [ "$UBUNTU_VERSION" == "$v" ]; then
        IS_SUPPORTED=true
        break
    fi
done

if [ "$IS_SUPPORTED" = false ]; then
    echo "Peringatan: Versi Ubuntu ${UBUNTU_VERSION} belum diuji secara eksplisit oleh script ini."
    echo "Script akan tetap dicoba dijalankan, tapi periksa hasilnya dengan teliti."
fi

# Docker resmi belum tentu langsung menyediakan repo untuk codename baru (mis. 26.04)
# di hari rilis. Jika codename tidak dikenali oleh repo Docker, fallback ke codename
# stable terakhir yang didukung (noble/24.04).
DOCKER_CODENAME="$UBUNTU_CODENAME"
FALLBACK_CODENAME="noble"

# Update sistem
echo "[1/9] Memperbarui paket sistem..."
apt update && apt upgrade -y

# Instalasi paket yang diperlukan
echo "[2/9] Menginstal paket yang diperlukan..."
apt install -y apt-transport-https ca-certificates curl software-properties-common gnupg lsb-release ufw fail2ban

# Menambahkan Docker repository
echo "[3/9] Menambahkan Docker repository..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Cek apakah codename saat ini sudah tersedia di repo Docker; kalau belum, fallback
if curl -fsSL "https://download.docker.com/linux/ubuntu/dists/${DOCKER_CODENAME}/Release" -o /dev/null 2>/dev/null; then
    echo "Repo Docker tersedia untuk codename '${DOCKER_CODENAME}'."
else
    echo "Repo Docker belum tersedia untuk codename '${DOCKER_CODENAME}', menggunakan fallback '${FALLBACK_CODENAME}'."
    DOCKER_CODENAME="$FALLBACK_CODENAME"
fi

echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu ${DOCKER_CODENAME} stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt update

# Instalasi Docker Engine
echo "[4/9] Menginstal Docker Engine..."
apt install -y docker-ce docker-ce-cli containerd.io

# Menambahkan pengguna saat ini ke grup docker (jika tidak root)
if [ "$SUDO_USER" ]; then
    echo "[5/9] Menambahkan pengguna $SUDO_USER ke grup docker..."
    usermod -aG docker "$SUDO_USER"
    echo "Pengguna $SUDO_USER ditambahkan ke grup docker. Log out dan log in kembali untuk menggunakan Docker tanpa sudo."
fi

# Instalasi Docker Compose
echo "[6/9] Menginstal Docker Compose..."
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Konfigurasi Firewall (UFW)
echo "[7/9] Mengkonfigurasi Firewall..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow http
ufw allow https
ufw --force enable

# Hardening SSH: disable password authentication
echo "[8/9] Menonaktifkan SSH password authentication..."

SSHD_CONFIG="/etc/ssh/sshd_config"
SSHD_CONFIG_D="/etc/ssh/sshd_config.d/99-disable-password-auth.conf"

# Cek apakah ada authorized_keys untuk user yang login, supaya tidak terkunci
KEY_CHECK_USER="${SUDO_USER:-root}"
KEY_CHECK_HOME=$(eval echo "~${KEY_CHECK_USER}")

if [ ! -s "${KEY_CHECK_HOME}/.ssh/authorized_keys" ]; then
    echo "PERINGATAN: Tidak ditemukan file authorized_keys untuk user '${KEY_CHECK_USER}'."
    echo "Menonaktifkan password authentication SEKARANG berisiko mengunci Anda dari server ini."
    echo "Melewati langkah disable password auth. Tambahkan SSH key terlebih dahulu, lalu jalankan ulang bagian ini."
else
    # Gunakan drop-in config supaya tidak perlu edit sshd_config utama secara langsung
    cat > "$SSHD_CONFIG_D" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
EOF

    # Pastikan konfigurasi lama di sshd_config tidak menimpa drop-in (opsional, aman untuk dikomentari)
    sed -i -E 's/^#?PasswordAuthentication\s+.*/PasswordAuthentication no/' "$SSHD_CONFIG" || true

    # Validasi konfigurasi sebelum restart
    if sshd -t; then
        systemctl restart ssh || systemctl restart sshd
        echo "Password authentication SSH berhasil dinonaktifkan. Login hanya via SSH key."
    else
        echo "Konfigurasi sshd tidak valid, perubahan dibatalkan. Periksa manual di $SSHD_CONFIG_D"
        rm -f "$SSHD_CONFIG_D"
    fi
fi

# Instalasi dan aktivasi Fail2ban
echo "[9/9] Mengaktifkan Fail2ban..."

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh
EOF

systemctl enable fail2ban
systemctl restart fail2ban

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
echo "--------------------"
echo "Fail2ban Status:"
fail2ban-client status
echo "--------------------"
echo "SSH Password Auth:"
grep -Ri "PasswordAuthentication" /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null || true
echo "======================================================"

echo "Setup selesai! Server Anda telah dikonfigurasi dengan Docker, Docker Compose, Firewall, SSH hardening, dan Fail2ban."
echo "Docker daemon sudah berjalan dan dimulai secara otomatis saat boot."
echo "Firewall telah diaktifkan dengan port SSH, HTTP, dan HTTPS terbuka."
echo "PENTING: Pastikan Anda masih bisa login via SSH key SEBELUM menutup sesi terminal ini."
