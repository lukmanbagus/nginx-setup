#!/bin/bash

# Script untuk menginstall dan mengkonfigurasi Nginx dengan domain dinamis
# Untuk Ubuntu 22.04

# Exit script jika terjadi error
set -e

# Fungsi untuk menampilkan cara penggunaan
usage() {
    echo "Penggunaan: $0 --domain=nama.domain.com [--ssl] [--email=email@domain.com]"
    echo ""
    echo "Opsi:"
    echo "  --domain=DOMAIN      Domain yang akan dikonfigurasi (wajib)"
    echo "  --ssl                Install sertifikat SSL dengan Certbot (opsional)"
    echo "  --email=EMAIL        Email untuk pendaftaran Let's Encrypt (opsional, diperlukan jika menggunakan --ssl)"
    echo ""
    echo "Contoh:"
    echo "  $0 --domain=wapi.lukmanbagus.com"
    echo "  $0 --domain=wapi.lukmanbagus.com --ssl --email=admin@lukmanbagus.com"
    exit 1
}

# Default values
INSTALL_SSL=false
EMAIL=""

# Parse command line arguments
for arg in "$@"; do
    case $arg in
        --domain=*)
            DOMAIN="${arg#*=}"
            ;;
        --ssl)
            INSTALL_SSL=true
            ;;
        --email=*)
            EMAIL="${arg#*=}"
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Error: Parameter tidak dikenal: $arg"
            usage
            ;;
    esac
done

# Validasi parameter yang diperlukan
if [ -z "$DOMAIN" ]; then
    echo "Error: Parameter domain wajib diisi"
    usage
fi

if [ "$INSTALL_SSL" = true ] && [ -z "$EMAIL" ]; then
    echo "Error: Parameter email wajib diisi saat menggunakan opsi --ssl"
    usage
fi

# Pastikan script dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    echo "Script ini harus dijalankan sebagai root atau dengan sudo"
    exit 1
fi

echo "Akan mengkonfigurasi Nginx untuk domain: $DOMAIN"
if [ "$INSTALL_SSL" = true ]; then
    echo "Sertifikat SSL akan diinstall dengan email: $EMAIL"
fi

# Konfirmasi untuk melanjutkan
read -p "Lanjutkan instalasi? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Instalasi dibatalkan."
    exit 0
fi

# Update sistem dan install Nginx
echo "Memperbarui sistem dan menginstall Nginx..."
apt update
apt install -y nginx

# Mengaktifkan Nginx sebagai service
echo "Memulai dan mengaktifkan Nginx..."
systemctl start nginx
systemctl enable nginx

# Mengizinkan Nginx melalui firewall jika UFW aktif
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo "Mengkonfigurasi firewall untuk Nginx..."
    ufw allow 'Nginx Full'
fi

# Membuat direktori untuk website
echo "Membuat direktori untuk website..."
mkdir -p /var/www/$DOMAIN
chown -R www-data:www-data /var/www/$DOMAIN
chmod -R 755 /var/www/$DOMAIN

# Membuat halaman HTML sederhana untuk pengujian
echo "Membuat halaman HTML pengujian..."
cat > /var/www/$DOMAIN/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Selamat Datang di $DOMAIN</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
        }
        h1 {
            color: #333;
            text-align: center;
        }
        p {
            color: #666;
        }
    </style>
</head>
<body>
    <h1>Selamat Datang di $DOMAIN</h1>
    <p>Jika Anda melihat halaman ini, berarti Nginx sudah berhasil diinstal dan dikonfigurasi untuk domain $DOMAIN.</p>
    <p>Server ini diatur secara otomatis menggunakan script instalasi.</p>
    <p>Tanggal instalasi: $(date)</p>
</body>
</html>
EOF

# Membuat konfigurasi server block Nginx
echo "Membuat konfigurasi server block Nginx..."
cat > /etc/nginx/sites-available/$DOMAIN << EOF
server {
    listen 80;
    listen [::]:80;

    server_name $DOMAIN;
    root /var/www/$DOMAIN;
    index index.html index.htm index.php;

    location / {
        try_files \$uri \$uri/ =404;
    }

    access_log /var/log/nginx/$DOMAIN\_access.log;
    error_log /var/log/nginx/$DOMAIN\_error.log;
}
EOF

# Mengaktifkan server block
echo "Mengaktifkan server block..."
ln -sf /etc/nginx/sites-available/$DOMAIN /etc/nginx/sites-enabled/

# Memeriksa konfigurasi Nginx
echo "Memeriksa konfigurasi Nginx..."
nginx -t

# Restart Nginx untuk menerapkan konfigurasi baru
echo "Merestart Nginx..."
systemctl restart nginx

# Install Certbot untuk sertifikat SSL (jika opsi --ssl diberikan)
if [ "$INSTALL_SSL" = true ]; then
    echo "Menginstall Certbot untuk SSL..."
    apt install -y certbot python3-certbot-nginx
    
    # Mengaktifkan repository universe jika belum
    add-apt-repository universe -y
    apt update
    
    echo "Mendapatkan sertifikat SSL untuk $DOMAIN..."
    certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $EMAIL
    
    echo "Sertifikat SSL berhasil dipasang."
fi

echo "==============================================================="
echo "Setup selesai! Nginx telah dikonfigurasi untuk $DOMAIN"
echo "Pastikan DNS A record untuk $DOMAIN mengarah ke IP server ini."
echo "Halaman pengujian tersedia di: http://$DOMAIN"
if [ "$INSTALL_SSL" = true ]; then
    echo "Site juga tersedia dengan HTTPS: https://$DOMAIN"
else
    echo "Untuk menginstall SSL, jalankan script ini lagi dengan parameter: --ssl --email=your-email@domain.com"
fi
echo "==============================================================="