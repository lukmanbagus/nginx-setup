#!/bin/bash
# ============================================================================
#  Server Setup Wizard
#  ----------------------------------------------------------------------------
#  Script interaktif untuk menyiapkan server kosong (bare server) dari nol.
#  Mendeteksi OS/distro secara otomatis lalu menuntun Anda melalui:
#    1. Update sistem
#    2. Hardening dasar (Firewall, SSH hardening, Fail2ban)
#    3. Instalasi aplikasi pilihan (multi-select interaktif)
#
#  Distro yang didukung:
#    Debian, Ubuntu, RedHat (RHEL), Fedora, Arch, Alpine, OpenSUSE,
#    FreeBSD, CentOS, RockyLinux, AlmaLinux, Oracle Linux, Manjaro, dll.
#
#  Aplikasi yang dapat diinstall:
#    Docker, Dokploy, Portainer, CyberPanel, CloudPanel, FastPanel,
#    HestiaCP, aaPanel
# ============================================================================

set -eo pipefail

# ──────────────────────────────────────────────────────────────────────────────
#  Konstanta & warna
# ──────────────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Daftar aplikasi yang dapat diinstall (label untuk menu)
APP_LABELS=(
    "Docker"
    "Dokploy"
    "Portainer"
    "CyberPanel"
    "CloudPanel"
    "FastPanel"
    "HestiaCP"
    "aaPanel"
)

# Variabel global yang diisi saat deteksi OS
OS_ID=""
OS_ID_LIKE=""
OS_NAME=""
OS_VERSION=""
DISTRO_FAMILY=""          # debian | rhel | arch | alpine | suse | freebsd
PM=""                     # apt | dnf | yum | pacman | apk | zypper | pkg
INIT_SYSTEM="systemd"     # systemd | openrc | bsd-init

# Hasil pilihan menu (array of index)
MENU_RESULT=()

# ──────────────────────────────────────────────────────────────────────────────
#  Helper output
# ──────────────────────────────────────────────────────────────────────────────
log_info()    { echo -e "${CYAN}[*]${NC} $*"; }
log_ok()      { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
log_error()   { echo -e "${RED}[-]${NC} $*" >&2; }
log_step()    { echo -e "\n${BLUE}==>${NC} ${BOLD}$*${NC}"; }

confirm() {
    # confirm "Pesan?" [default_y/n]
    local prompt="$1"
    local default="${2:-y}"
    local hint
    if [ "$default" = "y" ]; then hint="[Y/n]"; else hint="[y/N]"; fi
    local answer
    read -rp "$(echo -e "${BOLD}$prompt${NC} $hint ")" answer </dev/tty
    answer="${answer:-$default}"
    [[ "$answer" =~ ^[Yy]$ ]]
}

# ──────────────────────────────────────────────────────────────────────────────
#  Deteksi OS & Distro
# ──────────────────────────────────────────────────────────────────────────────
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_ID_LIKE="${ID_LIKE:-}"
        OS_NAME="${PRETTY_NAME:-${NAME:-unknown}}"
        OS_VERSION="${VERSION_ID:-}"
    elif [ -x /usr/sbin/freebsd-version ] || [ "$(uname -o 2>/dev/null)" = "FreeBSD" ] || [ "$(uname -s)" = "FreeBSD" ]; then
        OS_ID="freebsd"
        OS_NAME="FreeBSD $(freebsd-version -u 2>/dev/null || uname -r)"
        OS_VERSION="$(uname -r)"
        OS_ID_LIKE=""
    else
        OS_ID="unknown"
        OS_NAME="$(uname -s) $(uname -r)"
        OS_VERSION="$(uname -r)"
    fi

    # Tentukan keluarga distro & package manager
    local id="$OS_ID"
    case "$id" in
        debian|ubuntu|linuxmint|pop|elementary|kali|raspbian)
            DISTRO_FAMILY="debian"; PM="apt" ;;
        centos|rhel|rocky|almalinux|fedora|ol|cloudlinux|amzn)
            DISTRO_FAMILY="rhel"
            if command -v dnf &>/dev/null; then PM="dnf"
            elif command -v yum &>/dev/null; then PM="yum"
            else PM="dnf"; fi ;;
        arch|manjaro|garuda|endeavouros|artix)
            DISTRO_FAMILY="arch"; PM="pacman" ;;
        alpine)
            DISTRO_FAMILY="alpine"; PM="apk" ;;
        opensuse*|suse|sles|slemicro)
            DISTRO_FAMILY="suse"; PM="zypper" ;;
        freebsd)
            DISTRO_FAMILY="freebsd"; PM="pkg" ;;
        *)
            # fallback: cek ID_LIKE lalu command availability
            case "$OS_ID_LIKE" in
                *debian*|*ubuntu*) DISTRO_FAMILY="debian" ;;
                *rhel*|*fedora*|*centos*) DISTRO_FAMILY="rhel" ;;
                *arch*) DISTRO_FAMILY="arch" ;;
                *suse*) DISTRO_FAMILY="suse" ;;
                *alpine*) DISTRO_FAMILY="alpine" ;;
                *) DISTRO_FAMILY="unknown" ;;
            esac
            if   command -v apt-get &>/dev/null; then PM="apt"
            elif command -v dnf     &>/dev/null; then PM="dnf"
            elif command -v yum    &>/dev/null; then PM="yum"
            elif command -v pacman &>/dev/null; then PM="pacman"
            elif command -v apk    &>/dev/null; then PM="apk"
            elif command -v zypper &>/dev/null; then PM="zypper"
            elif command -v pkg    &>/dev/null; then PM="pkg"
            else PM="unknown"; fi
            ;;
    esac

    # Tentukan init system
    if [ "$DISTRO_FAMILY" = "alpine" ]; then
        INIT_SYSTEM="openrc"
    elif [ "$DISTRO_FAMILY" = "freebsd" ]; then
        INIT_SYSTEM="bsd-init"
    elif [ "$id" = "artix" ] || [ "$OS_ID_LIKE" = "artix" ]; then
        INIT_SYSTEM="other"
    else
        INIT_SYSTEM="systemd"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
#  Abstraksi package manager
# ──────────────────────────────────────────────────────────────────────────────
pkg_update() {
    case "$PM" in
        apt)    apt-get update && DEBIAN_FRONTEND=noninteractive apt-get -y upgrade ;;
        dnf)    dnf -y check-update 2>/dev/null || true; dnf -y upgrade ;;
        yum)    yum -y update ;;
        pacman) pacman -Syu --noconfirm ;;
        apk)    apk update && apk upgrade --no-cache ;;
        zypper) zypper --non-interactive --gpg-auto-import-keys refresh && zypper --non-interactive update ;;
        pkg)    pkg update -f && pkg upgrade -y ;;
        *)      log_warn "Package manager tidak dikenal, skip update sistem"; return 0 ;;
    esac
}

pkg_install() {
    # pkg_install <pkg1> [pkg2 ...]
    [ $# -eq 0 ] && return 0
    case "$PM" in
        apt)    DEBIAN_FRONTEND=noninteractive apt-get install -y "$@" ;;
        dnf)    dnf install -y "$@" ;;
        yum)    yum install -y "$@" ;;
        pacman) pacman -S --noconfirm --needed "$@" ;;
        apk)    apk add --no-cache "$@" ;;
        zypper) zypper --non-interactive install "$@" ;;
        pkg)    pkg install -y "$@" ;;
        *)      log_warn "Tidak bisa install '$*' (package manager tidak dikenal)"; return 1 ;;
    esac
}

# Jalankan service sesuai init system
svc_enable() { # svc_enable <service>
    case "$INIT_SYSTEM" in
        systemd) systemctl enable --now "$1" 2>/dev/null || true ;;
        openrc) rc-update add "$1" default 2>/dev/null; rc-service "$1" start 2>/dev/null || true ;;
        bsd-init) sysrc "${1}_enable=YES" 2>/dev/null; service "$1" start 2>/dev/null || true ;;
        *) log_warn "Tidak dapat mengaktifkan service '$1' (init: $INIT_SYSTEM)" ;;
    esac
}

svc_restart() { # svc_restart <service>
    case "$INIT_SYSTEM" in
        systemd) systemctl restart "$1" 2>/dev/null || true ;;
        openrc) rc-service "$1" restart 2>/dev/null || true ;;
        bsd-init) service "$1" restart 2>/dev/null || true ;;
        *) : ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────────────
#  Menu checklist multi-select (spasi = toggle, panah = navigasi, enter = lanjut)
# ──────────────────────────────────────────────────────────────────────────────
checklist_menu() {
    # $1  = judul menu
    # $2  = footer/help (opsional)
    # Mengisi global MENU_RESULT dengan index item yang dipilih
    local title="$1"
    local footer="${2:-}"
    local -a labels=("${APP_LABELS[@]}")
    local n=${#labels[@]}
    local -a selected=()
    local i
    # MENU_SELECT_ALL_DEFAULT=1 -> semua item terpilih di awal
    local initial=0
    [ "${MENU_SELECT_ALL_DEFAULT:-0}" = "1" ] && initial=1
    for ((i=0; i<n; i++)); do selected[i]=$initial; done
    MENU_SELECT_ALL_DEFAULT=0   # reset supaya tidak bocor ke pemanggilan berikutnya
    local cursor=0
    local redraw=1
    local key key2

    # sembunyikan kursor
    tput civis 2>/dev/null || printf '\e[?25l'

    while true; do
        if [ "$redraw" -eq 1 ]; then
            # cetak judul
            echo -e "\n${BOLD}${CYAN}${title}${NC}"
            echo -e "${DIM}Gunakan ↑/↓ untuk navigasi, SPASI untuk pilih, ENTER untuk lanjut${NC}"
            echo ""
            for ((i=0; i<n; i++)); do
                local mark=" "
                [ "${selected[i]}" -eq 1 ] && mark="x"
                if [ "$i" -eq "$cursor" ]; then
                    printf "  ${BOLD}\e[7m[%s] %s\e[0m${NC}\n" "$mark" "${labels[i]}"
                else
                    printf "  ${DIM}[%s] %s${NC}\n" "$mark" "${labels[i]}"
                fi
            done
            [ -n "$footer" ] && echo -e "\n${DIM}${footer}${NC}"
            redraw=0
        fi

        read -rsn1 key </dev/tty || true
        case "$key" in
            $'\x1b')
                # kemungkinan escape sequence panah
                read -rsn1 -t 0.1 key2 </dev/tty || key2=""
                if [ "$key2" = "[" ]; then
                    read -rsn1 -t 0.1 key2 </dev/tty || key2=""
                    case "$key2" in
                        A) cursor=$(( (cursor - 1 + n) % n )); redraw=1 ;;   # up
                        B) cursor=$(( (cursor + 1) % n )); redraw=1 ;;      # down
                    esac
                fi
                ;;
            ' ')
                if [ "${selected[cursor]}" -eq 1 ]; then selected[cursor]=0
                else selected[cursor]=1; fi
                redraw=1
                ;;
            '')
                # enter
                break
                ;;
            a|A)
                for ((i=0; i<n; i++)); do selected[i]=1; done; redraw=1 ;;
            n|N)
                for ((i=0; i<n; i++)); do selected[i]=0; done; redraw=1 ;;
        esac

        if [ "$redraw" -eq 1 ]; then
            # pindahkan kursor ke atas blok menu untuk redraw
            local lines_to_clear=$(( n + 4 ))
            [ -n "$footer" ] && lines_to_clear=$(( lines_to_clear + 2 ))
            printf "\e[%dA" "$lines_to_clear"
            printf "\e[J"   # hapus ke bawah
        fi
    done

    # tampilkan kursor kembali
    tput cnorm 2>/dev/null || printf '\e[?25h'

    MENU_RESULT=()
    for ((i=0; i<n; i++)); do
        [ "${selected[i]}" -eq 1 ] && MENU_RESULT+=("$i")
    done
}

# ──────────────────────────────────────────────────────────────────────────────
#  Hardening dasar
# ──────────────────────────────────────────────────────────────────────────────
setup_firewall() {
    log_step "Konfigurasi Firewall"
    case "$DISTRO_FAMILY" in
        debian)
            pkg_install ufw
            ufw --force reset >/dev/null 2>&1 || true
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow ssh
            ufw allow http
            ufw allow https
            ufw --force enable
            log_ok "Firewall (UFW) aktif: SSH, HTTP, HTTPS diizinkan"
            ;;
        rhel|suse)
            pkg_install firewalld
            svc_enable firewalld
            firewall-cmd --permanent --add-service=ssh    2>/dev/null || true
            firewall-cmd --permanent --add-service=http    2>/dev/null || true
            firewall-cmd --permanent --add-service=https   2>/dev/null || true
            firewall-cmd --reload 2>/dev/null || true
            log_ok "Firewall (firewalld) aktif: SSH, HTTP, HTTPS diizinkan"
            ;;
        arch)
            pkg_install ufw
            svc_enable ufw
            ufw --force reset >/dev/null 2>&1 || true
            ufw default deny incoming
            ufw default allow outgoing
            ufw allow ssh
            ufw allow http
            ufw allow https
            ufw --force enable
            log_ok "Firewall (UFW) aktif"
            ;;
        alpine)
            pkg_install iptables ip6tables
            iptables -F
            iptables -A INPUT -i lo -j ACCEPT
            iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
            iptables -A INPUT -p tcp --dport 22  -j ACCEPT
            iptables -A INPUT -p tcp --dport 80  -j ACCEPT
            iptables -A INPUT -p tcp --dport 443 -j ACCEPT
            iptables -P INPUT DROP
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            rc-update add iptables default 2>/dev/null || true
            /etc/init.d/iptables save 2>/dev/null || iptables-save > /etc/iptables/rules 2>/dev/null || true
            svc_enable iptables
            log_ok "Firewall (iptables) aktif: SSH, HTTP, HTTPS diizinkan"
            ;;
        freebsd)
            # gunakan pf (Packet Filter)
            if [ ! -f /etc/pf.conf ] || ! grep -q "server-setup" /etc/pf.conf 2>/dev/null; then
                cat >> /etc/pf.conf <<'EOF'

# --- server-setup ---
set block-policy return
scrub in all
block in all
pass out all keep state
pass in on lo0 keep state
pass in proto tcp from any to any port { 22, 80, 443 }
# --- end server-setup ---
EOF
            fi
            sysrc pf_enable=YES 2>/dev/null || true
            service pf start 2>/dev/null || service pf reload 2>/dev/null || true
            log_ok "Firewall (pf) aktif: SSH, HTTP, HTTPS diizinkan"
            ;;
        *)
            log_warn "Konfigurasi firewall otomatis belum didukung untuk '$OS_NAME'. Konfigurasi manual disarankan."
            ;;
    esac
}

setup_fail2ban() {
    log_step "Instalasi & aktivasi Fail2ban"
    pkg_install fail2ban

    local jail_conf="/etc/fail2ban/jail.local"
    local backend="auto"
    [ "$INIT_SYSTEM" = "systemd" ] && backend="systemd"

    cat > "$jail_conf" <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
backend  = $backend

[sshd]
enabled = true
port    = ssh
EOF

    svc_enable fail2ban
    svc_restart fail2ban
    log_ok "Fail2ban aktif (jail sshd diaktifkan)"
}

setup_ssh_hardening() {
    log_step "Hardening SSH (disable password authentication)"

    local check_user="${SUDO_USER:-root}"
    local check_home
    check_home=$(eval echo "~${check_user}")

    # Tawarkan penambahan SSH public key
    if confirm "Tambahkan SSH public key ke authorized_keys sekarang?" "y"; then
        read -rp "Tempelkan SSH public key (contoh: ssh-ed25519 AAAA... user@host): " ssh_pub_key </dev/tty
        if [ -n "$ssh_pub_key" ]; then
            mkdir -p "${check_home}/.ssh"
            touch "${check_home}/.ssh/authorized_keys"
            if grep -qF "$ssh_pub_key" "${check_home}/.ssh/authorized_keys" 2>/dev/null; then
                log_info "Key sudah ada di authorized_keys, tidak ditambahkan."
            else
                echo "$ssh_pub_key" >> "${check_home}/.ssh/authorized_keys"
                log_ok "Key ditambahkan ke ${check_home}/.ssh/authorized_keys"
            fi
            chmod 700 "${check_home}/.ssh"
            chmod 600 "${check_home}/.ssh/authorized_keys"
            chown -R "${check_user}:${check_user}" "${check_home}/.ssh"
        else
            log_warn "Tidak ada key yang dimasukkan."
        fi
    else
        log_info "Melewati penambahan SSH key."
    fi

    # Cek apakah sudah ada authorized_keys sebelum disable password auth
    if [ ! -s "${check_home}/.ssh/authorized_keys" ]; then
        log_warn "Tidak ada authorized_keys untuk '${check_user}'."
        log_warn "Menonaktifkan password auth sekarang berisiko mengunci Anda dari server."
        log_warn "Melewati disable password auth. Tambahkan SSH key dulu lalu jalankan ulang."
        return 0
    fi

    # Drop-in config (didukung OpenSSH modern) atau edit langsung
    local sshd_main="/etc/ssh/sshd_config"
    local sshd_dir="/etc/ssh/sshd_config.d"
    local drop_in="${sshd_dir}/99-disable-password-auth.conf"

    if [ -d "$sshd_dir" ]; then
        # pastikan sshd_config meng-Include drop-in dir
        if ! grep -qiE "^[[:space:]]*Include[[:space:]]+${sshd_dir}([^[:alnum:]]|$)" "$sshd_main" 2>/dev/null; then
            echo "Include ${sshd_dir}/*.conf" >> "$sshd_main"
        fi
        mkdir -p "$sshd_dir"
        cat > "$drop_in" <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin prohibit-password
EOF
    else
        # edit langsung file utama
        sed -i -E 's/^#?\s*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_main"
        sed -i -E 's/^#?\s*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$sshd_main"
    fi

    # Validasi & restart sshd
    if sshd -t 2>/dev/null; then
        svc_restart ssh || svc_restart sshd
        log_ok "Password authentication SSH dinonaktifkan. Login hanya via SSH key."
    else
        log_error "Konfigurasi sshd tidak valid, perubahan dibatalkan."
        rm -f "$drop_in"
    fi
}

# ──────────────────────────────────────────────────────────────────────────────
#  Installer aplikasi
# ──────────────────────────────────────────────────────────────────────────────
install_docker() {
    log_step "Instalasi Docker"
    if command -v docker &>/dev/null; then
        log_info "Docker sudah terinstall: $(docker --version)"
        return 0
    fi

    case "$DISTRO_FAMILY" in
        alpine)
            pkg_install docker docker-cli-compose docker-openrc
            svc_enable docker
            ;;
        arch)
            pkg_install docker docker-compose
            svc_enable docker
            ;;
        freebsd)
            log_error "Docker tidak didukung native di FreeBSD. Melewati."
            return 1
            ;;
        debian|rhel|suse)
            # convenience script resmi Docker mendukung banyak distro
            if command -v curl &>/dev/null || pkg_install curl; then
                curl -fsSL https://get.docker.com | sh
                svc_enable docker
                svc_enable containerd 2>/dev/null || true
            else
                log_error "Tidak dapat mengunduh installer Docker (curl tidak tersedia)"
                return 1
            fi
            ;;
        *)
            log_error "Docker belum didukung otomatis untuk '$OS_NAME'."
            return 1
            ;;
    esac

    # Tambahkan user ke grup docker
    if [ -n "${SUDO_USER:-}" ]; then
        usermod -aG docker "$SUDO_USER" 2>/dev/null || true
        log_info "User '$SUDO_USER' ditambahkan ke grup docker. Logout & login kembali untuk pakai Docker tanpa sudo."
    fi

    # Instal docker-compose standalone (v1) bila belum ada
    if ! command -v docker-compose &>/dev/null; then
        local compose_ver
        compose_ver=$(curl -s https://api.github.com/repos/docker/compose/releases/latest \
            | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' 2>/dev/null || echo "")
        if [ -n "$compose_ver" ]; then
            curl -L "https://github.com/docker/compose/releases/download/${compose_ver}/docker-compose-$(uname -s)-$(uname -m)" \
                -o /usr/local/bin/docker-compose 2>/dev/null && \
                chmod +x /usr/local/bin/docker-compose && \
                log_ok "docker-compose ${compose_ver} terinstall"
        fi
    fi

    log_ok "Docker terinstall: $(docker --version 2>/dev/null || echo 'OK')"
}

install_dokploy() {
    log_step "Instalasi Dokploy"
    if ! command -v docker &>/dev/null; then
        log_error "Dokploy membutuhkan Docker. Install Docker terlebih dahulu."
        return 1
    fi
    curl -fsSL https://dokploy.com/install.sh | bash
    log_ok "Dokploy terinstall. Akses via http://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'server-ip'):3000"
}

install_portainer() {
    log_step "Instalasi Portainer"
    if ! command -v docker &>/dev/null; then
        log_error "Portainer membutuhkan Docker. Install Docker terlebih dahulu."
        return 1
    fi
    docker volume create portainer_data >/dev/null 2>&1 || true
    docker run -d \
        -p 8000:8000 -p 9443:9443 \
        --name portainer --restart=always \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v portainer_data:/data \
        portainer/portainer-ce:latest
    log_ok "Portainer terinstall. Akses via https://$(hostname -I 2>/dev/null | awk '{print $1}' || echo 'server-ip'):9443"
}

install_cyberpanel() {
    log_step "Instalasi CyberPanel"
    if [[ "$DISTRO_FAMILY" != "debian" && "$DISTRO_FAMILY" != "rhel" ]]; then
        log_warn "CyberPanel resmi hanya mendukung Ubuntu / Alma / Rocky / RHEL / CloudLinux."
        confirm "Tetap lanjutkan instalasi (berisiko)?" "n" || return 1
    fi
    log_info "Installer CyberPanel interaktif akan dimulai, ikuti instruksinya."
    sh <(curl -s https://raw.githubusercontent.com/usmannasir/cyberpanel/stable/install/install.sh)
    log_ok "CyberPanel terinstall."
}

install_cloudpanel() {
    log_step "Instalasi CloudPanel"
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        log_error "CloudPanel hanya mendukung Debian & Ubuntu."
        return 1
    fi
    curl -sS https://installer.cloudpanel.io/ce/v2/install.sh -o /tmp/clp-install.sh
    bash /tmp/clp-install.sh
    log_ok "CloudPanel terinstall."
}

install_fastpanel() {
    log_step "Instalasi FastPanel"
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        log_error "FastPanel hanya mendukung Debian & Ubuntu."
        return 1
    fi
    curl -sS https://repo.fastpanel.direct/install_fastpanel.sh -o /tmp/fp-install.sh
    bash /tmp/fp-install.sh
    log_ok "FastPanel terinstall."
}

install_hestiacp() {
    log_step "Instalasi HestiaCP"
    if [[ "$DISTRO_FAMILY" != "debian" ]]; then
        log_error "HestiaCP hanya mendukung Debian & Ubuntu."
        return 1
    fi
    curl -sS https://raw.githubusercontent.com/hestiacp/hestiacp/release/install/hst-install.sh -o /tmp/hst-install.sh
    bash /tmp/hst-install.sh
    log_ok "HestiaCP terinstall."
}

install_aapanel() {
    log_step "Instalasi aaPanel"
    if [[ "$DISTRO_FAMILY" != "debian" && "$DISTRO_FAMILY" != "rhel" ]]; then
        log_error "aaPanel hanya mendukung CentOS/Debian/Ubuntu."
        return 1
    fi
    curl -sS https://raw.githubusercontent.com/aapanel/aapanel/master/script/aapanel.sh -o /tmp/aapanel-install.sh
    bash /tmp/aapanel-install.sh
    log_ok "aaPanel terinstall."
}

# ──────────────────────────────────────────────────────────────────────────────
#  Verifikasi
# ──────────────────────────────────────────────────────────────────────────────
verify_installation() {
    log_step "Verifikasi Instalasi"
    echo "------------------------------------------------------------"

    if command -v docker &>/dev/null; then
        echo -e "${GREEN}Docker:${NC}      $(docker --version 2>/dev/null)"
    else
        echo -e "${DIM}Docker:      tidak terinstall${NC}"
    fi

    if command -v docker-compose &>/dev/null; then
        echo -e "${GREEN}Compose:${NC}    $(docker-compose --version 2>/dev/null)"
    fi

    if command -v fail2ban-client &>/dev/null; then
        echo -e "${GREEN}Fail2ban:${NC}   $(fail2ban-client status 2>/dev/null | head -1 || echo 'aktif')"
    fi

    case "$DISTRO_FAMILY" in
        debian|arch) ufw status verbose 2>/dev/null | head -5 ;;
        rhel|suse)   firewall-cmd --list-all 2>/dev/null | head -5 ;;
        alpine)      iptables -S 2>/dev/null | head -8 ;;
        freebsd)     pfctl -s rules 2>/dev/null | head -5 ;;
    esac

    echo -e "${GREEN}SSH PassAuth:${NC} $(grep -Ri 'PasswordAuthentication' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | tail -1 || echo 'default')"
    echo "------------------------------------------------------------"
}

# ──────────────────────────────────────────────────────────────────────────────
#  Wizard utama
# ──────────────────────────────────────────────────────────────────────────────
main() {
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${BLUE}${BOLD}            SERVER SETUP WIZARD${NC}"
    echo -e "${BLUE}======================================================${NC}"
    echo -e "${DIM}Setup interaktif untuk menyiapkan server kosong${NC}"
    echo ""

    # 1. Cek root
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Script ini harus dijalankan sebagai root atau dengan sudo."
        exit 1
    fi

    # 2. Deteksi OS
    detect_os
    log_step "Deteksi Sistem Operasi"
    echo -e "  ${BOLD}Distro:${NC}   $OS_NAME"
    echo -e "  ${BOLD}ID:${NC}       $OS_ID${OS_ID_LIKE:+ (like: $OS_ID_LIKE)}"
    echo -e "  ${BOLD}Versi:${NC}    ${OS_VERSION:-tidak diketahui}"
    echo -e "  ${BOLD}Family:${NC}   $DISTRO_FAMILY"
    echo -e "  ${BOLD}Pkg mgr:${NC}  $PM"
    echo -e "  ${BOLD}Init:${NC}     $INIT_SYSTEM"

    if [ "$DISTRO_FAMILY" = "unknown" ] || [ "$PM" = "unknown" ]; then
        log_warn "Distro/package manager tidak dikenali. Script mungkin tidak berjalan optimal."
        confirm "Lanjutkan anyway?" "n" || exit 0
    fi

    # 3. Update sistem
    if confirm "Lakukan update & upgrade sistem sekarang?" "y"; then
        log_step "Update & upgrade sistem"
        pkg_update
        # pastikan curl tersedia untuk installer lain
        command -v curl >/dev/null 2>&1 || pkg_install curl
        command -v wget >/dev/null 2>&1 || pkg_install wget 2>/dev/null || true
    fi

    # 4. Pilih hardening dasar (reuse checklist_menu dengan swap APP_LABELS)
    log_step "Pilih hardening dasar server"
    local -a _APP_BACKUP=("${APP_LABELS[@]}")
    APP_LABELS=("Firewall (buka SSH/HTTP/HTTPS)" "SSH Hardening (disable password auth)" "Fail2ban (proteksi brute-force)")
    MENU_SELECT_ALL_DEFAULT=1   # hardening defaultnya semua aktif
    checklist_menu "Pilih hardening dasar (semua aktif by default)"
    APP_LABELS=("${_APP_BACKUP[@]}")
    local -a hsel=("${MENU_RESULT[@]}")

    # 5. Pilih aplikasi yang ingin diinstall
    checklist_menu "Pilih aplikasi yang ingin diinstall" "Docker dibutuhkan oleh Dokploy & Portainer"

    # Helper: cek apakah index dipilih
    _is_selected() { local t="$1" k; for k in "$@"; do [ "$k" = "$t" ] && return 0; done; return 1; }

    # Tampilkan ringkasan pilihan
    echo ""
    log_step "Ringkasan pilihan"
    echo -e "${BOLD}Hardening:${NC}"
    _is_selected 0  "${hsel[@]}"  && echo "  - Firewall"
    _is_selected 1  "${hsel[@]}"  && echo "  - SSH Hardening"
    _is_selected 2  "${hsel[@]}"  && echo "  - Fail2ban"
    echo -e "${BOLD}Aplikasi:${NC}"
    if [ ${#MENU_RESULT[@]} -eq 0 ]; then
        echo "  (tidak ada aplikasi dipilih)"
    else
        for i in "${MENU_RESULT[@]}"; do echo "  - ${APP_LABELS[i]}"; done
    fi
    echo ""

    # Cek dependensi Docker untuk Dokploy/Portainer
    local need_docker=0
    for i in "${MENU_RESULT[@]}"; do
        case "${APP_LABELS[i]}" in
            "Dokploy"|"Portainer") need_docker=1 ;;
        esac
    done
    local has_docker=0
    for i in "${MENU_RESULT[@]}"; do
        [ "${APP_LABELS[i]}" = "Docker" ] && has_docker=1
    done
    if [ "$need_docker" -eq 1 ] && [ "$has_docker" -eq 0 ] && ! command -v docker &>/dev/null; then
        log_warn "Dokploy/Portainer membutuhkan Docker yang belum dipilih."
        if confirm "Tambahkan Docker ke daftar instalasi?" "y"; then
            # tambahkan index Docker (0) ke MENU_RESULT
            MENU_RESULT=(0 "${MENU_RESULT[@]}")
        fi
    fi

    if ! confirm "Mulai eksekusi setup dengan pilihan di atas?" "y"; then
        log_info "Setup dibatalkan."
        exit 0
    fi

    # ─── Eksekusi hardening ───
    _is_selected 0 "${hsel[@]}" && setup_firewall
    _is_selected 2 "${hsel[@]}" && setup_fail2ban
    _is_selected 1 "${hsel[@]}" && setup_ssh_hardening

    # ─── Eksekusi instalasi aplikasi ───
    # Docker pertama jika dipilih (karena dependensi)
    for i in "${MENU_RESULT[@]}"; do
        [ "${APP_LABELS[i]}" = "Docker" ] && install_docker
    done
    for i in "${MENU_RESULT[@]}"; do
        case "${APP_LABELS[i]}" in
            "Docker") ;; # sudah diinstall di atas
            "Dokploy")    install_dokploy ;;
            "Portainer")  install_portainer ;;
            "CyberPanel") install_cyberpanel ;;
            "CloudPanel") install_cloudpanel ;;
            "FastPanel")  install_fastpanel ;;
            "HestiaCP")   install_hestiacp ;;
            "aaPanel")    install_aapanel ;;
        esac
    done

    # ─── Verifikasi ───
    verify_installation

    echo ""
    echo -e "${GREEN}${BOLD}Setup selesai!${NC}"
    if _is_selected 1 "${hsel[@]}"; then
        echo -e "${YELLOW}PENTING: Pastikan Anda bisa login via SSH key SEBELUM menutup sesi terminal ini.${NC}"
    fi
}

main "$@"
