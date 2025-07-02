#!/bin/bash
if [[ -z "$RED" || -z "$GREEN" || -z "$YELLOW" || -z "$BLACK" || -z "$CYAN" || -z "$NC" || -z "$USERHOME" || -z "$USERNAME" ]]; then
    echo "Not running from install.sh. Please run install.sh."
    exit 1
fi

QUIET=false

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -q, --quiet      Suppress output messages"
    echo "  -u, --uninstall  Uninstall FTP server configuration"
    echo "  -s, --status     Check if FTP server is configured (exit 0 if yes, 1 if no)"
    echo "  -h, --help       Show this help message"
    echo ""
}

check_status() {
    local configured=true
    
    if ! dpkg -l | grep -q "^ii  vsftpd "; then
        configured=false
    fi
    
    if [[ ! -f /etc/vsftpd.conf ]] || ! grep -q "local_root=/home/\$USER" /etc/vsftpd.conf; then
        configured=false
    fi
    
    if ! systemctl is-enabled --quiet vsftpd 2>/dev/null; then
        configured=false
    fi
    
    if [[ "$configured" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

uninstall_ftp() {
    echo -e "${BLACK}[ INFO ]${NC} Uninstalling FTP server..."
    systemctl stop vsftpd 2>/dev/null || true
    systemctl disable vsftpd 2>/dev/null || true
    
    [[ -f /etc/vsftpd.conf.backup ]] && mv /etc/vsftpd.conf.backup /etc/vsftpd.conf
    
    apt remove --purge -y vsftpd 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    
    echo -e "${GREEN}[  OK  ]${NC} FTP server uninstalled successfully"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -u|--uninstall)
            [[ $EUID -ne 0 ]] && { echo -e "${RED}[ ERROR ]${NC} Uninstall requires root privileges"; exit 1; }
            uninstall_ftp
            exit 0
            ;;
        -s|--status)
            check_status
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}[ ERROR ]${NC} Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

trap 'echo -e "${RED}[ ERROR ]${NC} Command failed: $BASH_COMMAND"; echo "FAILED: $BASH_COMMAND" >> $USERHOME/info.log; exit 1' ERR
set -e

[[ $EUID -ne 0 ]] && { echo -e "${YELLOW}[ WARN ]${NC} Need sudo..."; sudo "$0" "$@"; exit $?; }

FTP_SERVER_IP=$(hostname -I | awk '{print $1}')
PORT="21"

echo -e "${BLACK}[ INFO ]${NC} Installing vsftpd FTP server..."

if ! dpkg -l | grep -q "^ii  vsftpd "; then
    echo -e "${BLACK}[ INFO ]${NC} Installing vsftpd package"
    apt update
    apt install -y vsftpd
else
    echo -e "${BLACK}[ INFO ]${NC} vsftpd already installed"
fi

echo -e "${BLACK}[ INFO ]${NC} Stopping vsftpd for configuration..."
systemctl stop vsftpd 2>/dev/null || true

echo -e "${BLACK}[ INFO ]${NC} Configuring vsftpd..."
if [[ ! -f /etc/vsftpd.conf.backup ]]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.backup
fi

cat > /etc/vsftpd.conf << 'EOF'
listen=NO
listen_ipv6=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
local_root=/home/$USER
allow_writeable_chroot=YES
pasv_enable=YES
pasv_min_port=10000
pasv_max_port=10100
EOF

echo -e "${BLACK}[ INFO ]${NC} Configuring firewall for FTP..."
if command -v ufw &>/dev/null; then
    ufw allow 21/tcp 2>/dev/null || true
    ufw allow 10000:10100/tcp 2>/dev/null || true
elif command -v iptables &>/dev/null; then
    iptables -A INPUT -p tcp --dport 21 -j ACCEPT 2>/dev/null || true
    iptables -A INPUT -p tcp --dport 10000:10100 -j ACCEPT 2>/dev/null || true
fi

echo -e "${BLACK}[ INFO ]${NC} Starting and enabling vsftpd service..."
systemctl enable vsftpd
systemctl start vsftpd

echo -e "${GREEN}[  OK  ]${NC} FTP server ready!"
{
    echo -e "${YELLOW}FTP Server:${NC} $FTP_SERVER_IP"
    echo -e "${YELLOW}Login:${NC} $USERNAME"
    echo -e "${YELLOW}Port:${NC} $PORT"
    echo -e "${YELLOW}Directory:${NC} $USERHOME"
} >> $USERHOME/info.log
