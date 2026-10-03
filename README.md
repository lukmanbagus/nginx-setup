# Server Setup Wizard

Script Bash interaktif untuk menyiapkan server kosong (bare server) dari nol.
Mendeteksi OS/distro secara otomatis lalu menuntun Anda melalui wizard step-by-step:
update sistem, hardening dasar, dan instalasi aplikasi pilihan.

## Fitur

- **Deteksi OS otomatis** di awal wizard (distro, versi, family, package manager, init system)
- **Menu multi-select interaktif** — navigasi panah ↑/↓, SPASI untuk pilih, ENTER lanjut,
  `A` pilih semua, `N` kosongkan
- **Kompatibel banyak distro Linux**: Debian, Ubuntu, RedHat (RHEL), Fedora, Arch,
  Alpine, OpenSUSE, FreeBSD, CentOS, RockyLinux, AlmaLinux, Oracle Linux, Manjaro, dll.
- **Hardening dasar** (opsional, multi-select):
  - Firewall (membuka SSH/HTTP/HTTPS) — UFW / firewalld / iptables / pf sesuai distro
  - SSH Hardening (menonaktifkan password authentication, drop-in sshd config)
  - Fail2ban (proteksi brute-force SSH)
- **Instalasi aplikasi** pilihan:
  - Docker (+ Docker Compose)
  - Dokploy
  - Portainer
  - CyberPanel
  - CloudPanel
  - FastPanel
  - HestiaCP
  - aaPanel
- **Reverse proxy** (opsional, multi-entry) — untuk setiap entry diminta:
  - Domain (mis. `app.example.com`)
  - Target `container:port` atau `host:port` (mis. `webapp:3000`, `127.0.0.1:8080`)
  - Pilihan web server: **Nginx** atau **Apache**
  - Otomatis memasang web server, menulis virtualhost/server-block,
    membuka port HTTP/HTTPS di firewall, dan reload service
- **Penanganan dependensi otomatis** — Dokploy & Portainer membutuhkan Docker;
  script akan menawarkan menambahkan Docker bila belum dipilih.
- **Verifikasi instalasi** di akhir (status Docker, Fail2ban, Firewall, SSH,
  web server, dan daftar reverse proxy)

## Persyaratan

- Server Linux/FreeBSD dengan distro yang didukung
- Root atau sudo privileges
- Koneksi internet untuk instalasi paket

## Penggunaan

### 1. Clone repo
```bash
git clone https://github.com/lukmanbagus/nginx-setup.git && cd nginx-setup
```

### 2. Beri permission eksekusi
```bash
chmod +x setup.sh
```

### 3. Jalankan wizard
```bash
sudo ./setup.sh
```

Ikuti wizard step-by-step:
1. Pengecekan OS ditampilkan
2. Konfirmasi update & upgrade sistem
3. Pilih hardening dasar (multi-select, semua aktif by default)
4. Pilih aplikasi yang ingin diinstall (multi-select)
5. Setup reverse proxy (opsional, multi-entry: domain + container:port + web server)
6. Konfirmasi ringkasan pilihan
7. Eksekusi instalasi
8. Verifikasi

### Navigasi menu
| Tombol  | Aksi                          |
|---------|-------------------------------|
| ↑ / ↓   | Navigasi antar opsi           |
| Spasi   | Toggle pilih / batal pilih    |
| Enter   | Lanjut ke step berikutnya     |
| A       | Pilih semua                   |
| N       | Kosongkan semua               |

## Catatan kompatibilitas per distro

| Distro            | Firewall      | Docker native | Panel yang didukung            |
|-------------------|---------------|---------------|--------------------------------|
| Debian / Ubuntu   | UFW           | Ya            | Semua                          |
| RHEL / CentOS / Rocky / Alma | firewalld | Ya   | CyberPanel, aaPanel            |
| Fedora            | firewalld     | Ya            | CyberPanel, aaPanel            |
| Arch / Manjaro    | UFW           | Ya            | Docker (panel umumnya Debian-only) |
| Alpine            | iptables      | Ya (apk)      | Docker (panel umumnya Debian-only) |
| OpenSUSE          | firewalld     | Ya            | Docker (panel umumnya Debian-only) |
| FreeBSD           | pf            | Tidak native  | Tidak didukung (Docker)        |

> Catatan: CyberPanel, CloudPanel, FastPanel, HestiaCP, dan aaPanel secara resmi
> hanya mendukung Debian/Ubuntu (dan beberapa untuk RHEL family). Script akan
> memperingatkan bila Anda memilih panel pada distro yang tidak di dukung.

## Reverse proxy & jaringan container

Reverse proxy diarahkan ke `container:port` atau `host:port`. Agar web server di
host dapat menjangkau container Docker **berdasarkan nama**, pastikan:
- Container berada dalam Docker network yang sama dengan host, atau
- Gunakan `network_mode: host` di Docker Compose, atau
- Proxy ke `127.0.0.1:PORT` (port yang dipublikasikan container ke host).

Konfigurasi yang ditulis script:
- **Nginx**: `server` block dengan `proxy_pass` + header websocket (Upgrade/Connection)
  - Debian/Ubuntu: `/etc/nginx/sites-available/<domain>` + symlink di `sites-enabled`
  - RHEL/CentOS/Rocky/Alma/Fedora/Arch/Alpine/SUSE: `/etc/nginx/conf.d/<domain>.conf`
  - FreeBSD: `/usr/local/etc/nginx/conf.d/<domain>.conf`
- **Apache**: `<VirtualHost *:80>` dengan `ProxyPass`/`ProxyPassReverse` + `ProxyPreserveHost`
  - Debian/Ubuntu: `/etc/apache2/sites-available/<domain>.conf` + `a2ensite` + modul `proxy*`
  - RHEL family/SUSE: `/etc/httpd/conf.d/<domain>.conf`
  - FreeBSD: `/usr/local/etc/apache24/Includes/<domain>.conf`

> Tip: reverse proxy di sini hanya HTTP (port 80). Untuk HTTPS, jalankan
> Certbot setelahnya terhadap domain yang sudah dikonfigurasi.

## Peringatan keamanan

Saat SSH hardening diaktifkan, password authentication dinonaktifkan. Pastikan Anda
telah menambahkan SSH public key dan dapat login via key **sebelum** menutup sesi
terminal. Script akan memeriksa keberadaan `authorized_keys` dan menolak menonaktifkan
password auth bila belum ada key sama sekali.
