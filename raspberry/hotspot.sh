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
    echo "  -u, --uninstall  Uninstall hotspot setup"
    echo "  -s, --status     Check if hotspot is installed"
    echo "  -h, --help       Show this help message"
    echo ""
}

uninstall_hotspot() {
    chattr -i /etc/dhcpcd.conf 2>/dev/null || true
    chattr -i /etc/dnsmasq.conf 2>/dev/null || true
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    systemctl disable hostapd dnsmasq 2>/dev/null || true
    killall hostapd dnsmasq 2>/dev/null || true
    rm -f /etc/hostapd/hostapd.conf
    rm -f /etc/default/hostapd
    rm -f /etc/sysctl.d/99-ip-forward.conf
    rm -f /etc/iptables/rules.v4
    rm -f /etc/dnsmasq.conf
    rm -f /etc/dhcpcd.conf
    apt remove --purge -y hostapd dnsmasq iptables-persistent rfkill 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    iptables -F
    iptables -t nat -F
    echo 0 > /proc/sys/net/ipv4/ip_forward
    ip addr flush dev wlan0 2>/dev/null || true
    ip link set wlan0 down 2>/dev/null || true
    systemctl daemon-reload
    echo -e "${GREEN}[  OK  ]${NC} Hotspot uninstalled successfully"
}

check_status() {
    if ! command -v hostapd &>/dev/null; then exit 1; fi
    if ! command -v dnsmasq &>/dev/null; then exit 1; fi
    if ! command -v rfkill &>/dev/null; then exit 1; fi
    if ! [ -f /etc/dhcpcd.conf ]; then exit 1; fi
    if ! [ -f /etc/dnsmasq.conf ]; then exit 1; fi
    if ! [ -f /etc/hostapd/hostapd.conf ]; then exit 1; fi
    if ! grep -q "static ip_address=192.168.4.1/24" /etc/dhcpcd.conf; then exit 1; fi
    if ! grep -q "dhcp-range=192.168.4.2,192.168.4.20" /etc/dnsmasq.conf; then exit 1; fi
    if ! grep -q "ssid=wojtekojtek" /etc/hostapd/hostapd.conf; then exit 1; fi
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -u|--uninstall)
            [[ $EUID -ne 0 ]] && { echo -e "${RED}[ ERROR ]${NC} Uninstall requires root privileges"; exit 1; }
            uninstall_hotspot
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

trap 'echo -e "${RED}[ ERROR ]${NC} Command failed: $BASH_COMMAND"; exit 1' ERR
set -e

[[ $EUID -ne 0 ]] && { echo -e "${YELLOW}[ WARN ]${NC} Need sudo..."; sudo "$0" "$@"; exit $?; }

systemctl stop NetworkManager 2>/dev/null || true
systemctl disable NetworkManager 2>/dev/null || true
systemctl mask NetworkManager 2>/dev/null || true
systemctl stop systemd-networkd 2>/dev/null || true
systemctl disable systemd-networkd 2>/dev/null || true
systemctl mask systemd-networkd 2>/dev/null || true
chattr -i /etc/dhcpcd.conf 2>/dev/null || true

apt update
apt install -y hostapd dnsmasq iptables-persistent rfkill

cat > /etc/dhcpcd.conf <<EOF
interface eth0
static ip_address=192.168.1.105/24
static routers=192.168.1.1
static domain_name_servers=1.1.1.1

interface wlan0
static ip_address=192.168.4.1/24
nohook wpa_supplicant
EOF

chattr +i /etc/dhcpcd.conf || true

if [ -f /etc/network/interfaces ]; then
    sed -i '/iface eth0/d;/iface wlan0/d;/auto eth0/d;/auto wlan0/d' /etc/network/interfaces
fi

rfkill unblock wifi
rfkill unblock all
ip addr flush dev wlan0 || true
ip link set wlan0 down || true
sleep 2
ip link set wlan0 up || true
ip addr add 192.168.4.1/24 dev wlan0 || true
sleep 3

systemctl restart dhcpcd
sleep 2

cat > /etc/dnsmasq.conf <<EOF
interface=wlan0
bind-interfaces
dhcp-authoritative
dhcp-range=192.168.4.2,192.168.4.20,255.255.255.0,24h
dhcp-option=3,192.168.4.1
dhcp-option=6,1.1.1.1
server=1.1.1.1
server=1.0.0.1
domain=wlan
address=/gw.wlan/192.168.4.1
dhcp-leasefile=/var/lib/misc/dnsmasq.leases
log-dhcp
log-facility=/var/log/dnsmasq.log
EOF

if [ -d /etc/dnsmasq.d ]; then
    mkdir -p /tmp/dnsmasq-d-backup
    mv /etc/dnsmasq.d/* /tmp/dnsmasq-d-backup/ 2>/dev/null || true
fi
chattr +i /etc/dnsmasq.conf || true

systemctl restart dnsmasq

cat > /etc/hostapd/hostapd.conf <<EOF
interface=wlan0
driver=nl80211
ssid=wojtekojtek
hw_mode=g
channel=1
wpa=2
wpa_passphrase=wojtekojtek
ignore_broadcast_ssid=1
EOF
echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd

systemctl unmask hostapd
systemctl enable hostapd
systemctl restart hostapd

echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip-forward.conf
sysctl -w net.ipv4.ip_forward=1

iptables -F
iptables -t nat -F
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -A FORWARD -i eth0 -o wlan0 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i wlan0 -o eth0 -j ACCEPT
iptables -A INPUT -i wlan0 -j ACCEPT
mkdir -p /etc/iptables
iptables-save > /etc/iptables/rules.v4

mount | grep 'on / ' | grep -q 'ro,' && echo -e "${RED}[WARN] Root filesystem is read-only! Changes will not persist after reboot.${NC}"
mount | grep 'overlay' | grep 'on / ' && echo -e "${YELLOW}[WARN] Root filesystem is an overlay. Changes may not persist.${NC}"
grep -r 'dhcpcd.conf' /etc/rc.local /etc/init.d/ /etc/systemd/system/ /etc/crontab 2>/dev/null | grep -v 'No such file' && echo -e "${YELLOW}[WARN] Found references to dhcpcd.conf in startup scripts. Review above lines!${NC}"
chattr +i /etc/dhcpcd.conf 2>/dev/null || true

echo -e "${GREEN}[  OK  ]${NC} Hotspot setup complete!"
