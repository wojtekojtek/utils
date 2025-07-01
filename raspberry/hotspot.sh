#!/bin/bash
if [[ -z "$RED" || -z "$GREEN" || -z "$YELLOW" || -z "$BLACK" || -z "$CYAN" || -z "$NC" ]]; then
    echo "Not running from install.sh. Please run install.sh."
    exit 1
fi

QUIET=false

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -q, --quiet      Suppress output messages"
    echo "  -u, --uninstall  Uninstall hotspot configuration"
    echo "  -s, --status     Check if hotspot is configured (exit 0 if yes, 1 if no)"
    echo "  -h, --help       Show this help message"
    echo ""
    echo "This script starts/configures the WiFi hotspot."
}

check_status() {
    local configured=true
    
    if [[ ! -f /etc/hostapd/hostapd.conf ]] || ! grep -q "ssid=wojtekojtek" /etc/hostapd/hostapd.conf; then
        configured=false
    fi
    
    if [[ ! -f /etc/dnsmasq.conf ]] || ! grep -q "interface=wlan0" /etc/dnsmasq.conf; then
        configured=false
    fi
    
    if [[ ! -f /etc/dhcpcd.conf ]] || ! grep -q "static ip_address=192.168.4.1/24" /etc/dhcpcd.conf; then
        configured=false
    fi
    
    if [[ ! -f /usr/local/bin/hotspot ]]; then
        configured=false
    fi
    
    if [[ "$configured" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

uninstall_hotspot() {
    echo -e "${BLACK}[ INFO ]${NC} Stopping hotspot services..."
    systemctl stop hostapd dnsmasq 2>/dev/null || true
    systemctl disable hostapd dnsmasq 2>/dev/null || true
    killall hostapd dnsmasq 2>/dev/null || true
    
    echo -e "${BLACK}[ INFO ]${NC} Restoring original configurations..."
    [[ -f /etc/dhcpcd.conf.backup ]] && mv /etc/dhcpcd.conf.backup /etc/dhcpcd.conf
    [[ -f /etc/dnsmasq.conf.backup ]] && mv /etc/dnsmasq.conf.backup /etc/dnsmasq.conf
    
    echo -e "${BLACK}[ INFO ]${NC} Removing hotspot files..."
    rm -f /etc/hostapd/hostapd.conf
    rm -f /etc/default/hostapd
    rm -f /etc/sysctl.d/99-ip-forward.conf
    rm -f /etc/iptables/rules.v4
    rm -f /etc/hotspot_ip.conf
    rm -f /usr/local/bin/hotspot

    echo -e "${BLACK}[ INFO ]${NC} Removing installed packages..."
    apt remove --purge -y hostapd 2>/dev/null || true # we don't remove "dnsmasq iptables-persistent" for now, some other services may depend on them
    apt autoremove -y 2>/dev/null || true
    
    echo -e "${BLACK}[ INFO ]${NC} Clearing firewall rules..."
    iptables -F
    iptables -t nat -F
    echo 0 > /proc/sys/net/ipv4/ip_forward
    
    echo -e "${BLACK}[ INFO ]${NC} Resetting WiFi interface..."
    ip addr flush dev wlan0 2>/dev/null || true
    ip link set wlan0 down 2>/dev/null || true
    
    echo -e "${BLACK}[ INFO ]${NC} Restarting network services..."
    systemctl daemon-reload
    systemctl restart dhcpcd 2>/dev/null || true
    systemctl enable NetworkManager 2>/dev/null || true
    systemctl start NetworkManager 2>/dev/null || true
    
    echo -e "${GREEN}[  OK  ]${NC} Hotspot uninstalled successfully"
    echo -e "${BLACK}[ INFO ]${NC} You may need to reboot to fully restore WiFi functionality"
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

trap 'echo -e "${RED}[ ERROR ]${NC} Command failed: $BASH_COMMAND"; echo "FAILED: $BASH_COMMAND" >> $USERHOME/info.log; exit 1' ERR
set -e

[[ $EUID -ne 0 ]] && { echo -e "${YELLOW}[ WARN ]${NC} Need sudo..."; sudo -E "$0" $ARGS; exit $?; }

echo -e "${BLACK}[ INFO ]${NC} Copying hotspot to /usr/local/bin/hotspot"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cp "$SCRIPT_DIR/hotspot" /usr/local/bin/hotspot
chmod +x /usr/local/bin/hotspot

SSID="wojtekojtek"
PASSWORD="wojtekojtek"
CHANNEL="7"
INTERFACE="wlan0"
COUNTRY="PL"
HOTSPOT_IP="192.168.4.1"
DHCP_START="192.168.4.2"
DHCP_END="192.168.4.20"

if ! ip link show "$INTERFACE" &>/dev/null; then
    echo -e "${RED}[ ERROR ]${NC} WiFi interface $INTERFACE not found!"
    echo "FAILED: WiFi interface $INTERFACE not found!" >> $USERHOME/info.log
    exit 1
fi

INTERNET_IF=$(ip route | grep default | head -1 | awk '{print $5}')
if [[ -z "$INTERNET_IF" ]]; then
    echo -e "${RED}[ ERROR ]${NC} No internet connection found"
    echo "FAILED: No internet connection found" >> $USERHOME/info.log
    exit 1
fi

echo -e "${BLACK}[ INFO ]${NC} Setting up hotspot on $HOTSPOT_IP via $INTERNET_IF"

SERVICES_TO_STOP=""
systemctl is-active --quiet NetworkManager 2>/dev/null && SERVICES_TO_STOP="$SERVICES_TO_STOP NetworkManager"
systemctl is-active --quiet connman 2>/dev/null && SERVICES_TO_STOP="$SERVICES_TO_STOP connman"
systemctl is-active --quiet systemd-resolved 2>/dev/null && SERVICES_TO_STOP="$SERVICES_TO_STOP systemd-resolved"
systemctl is-active --quiet wpa_supplicant 2>/dev/null && SERVICES_TO_STOP="$SERVICES_TO_STOP wpa_supplicant"

if [[ -n "$SERVICES_TO_STOP" ]]; then
    echo -e "${BLACK}[ INFO ]${NC} Stopping conflicting services"
    systemctl stop $SERVICES_TO_STOP 2>/dev/null || true
    systemctl disable $SERVICES_TO_STOP 2>/dev/null || true
fi

CURRENT_IP=$(ip addr show "$INTERFACE" | grep 'inet ' | awk '{print $2}' | head -1)
if [[ "$CURRENT_IP" != "$HOTSPOT_IP/24" ]]; then
    echo -e "${BLACK}[ INFO ]${NC} Configuring WiFi interface"
    rfkill unblock wifi
    rfkill unblock all
    ip link set "$INTERFACE" down
    ip addr flush dev "$INTERFACE"
    ip link set "$INTERFACE" up
    ip addr add "$HOTSPOT_IP/24" dev "$INTERFACE"
fi

if ! grep -q "interface $INTERFACE" /etc/dhcpcd.conf || ! grep -q "static ip_address=$HOTSPOT_IP/24" /etc/dhcpcd.conf; then
    echo -e "${BLACK}[ INFO ]${NC} Configuring dhcpcd"
    cp /etc/dhcpcd.conf /etc/dhcpcd.conf.backup 2>/dev/null || true
    cat > /etc/dhcpcd.conf << EOF
interface $INTERFACE
static ip_address=$HOTSPOT_IP/24
nohook wpa_supplicant
EOF
fi

if ! grep -q "interface=$INTERFACE" /etc/dnsmasq.conf || ! grep -q "dhcp-range=$DHCP_START,$DHCP_END" /etc/dnsmasq.conf; then
    echo -e "${BLACK}[ INFO ]${NC} Configuring dnsmasq"
    cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup 2>/dev/null || true
    cat > /etc/dnsmasq.conf << EOF
interface=$INTERFACE
bind-interfaces
dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,24h
dhcp-option=3,$HOTSPOT_IP
dhcp-option=6,8.8.8.8,8.8.4.4
server=8.8.8.8
server=8.8.4.4
domain=wlan
address=/gw.wlan/$HOTSPOT_IP
EOF
fi

if ! grep -q "ssid=$SSID" /etc/hostapd/hostapd.conf || ! grep -q "interface=$INTERFACE" /etc/hostapd/hostapd.conf; then
    echo -e "${BLACK}[ INFO ]${NC} Configuring hostapd"
    cat > /etc/hostapd/hostapd.conf << EOF
country_code=$COUNTRY
interface=$INTERFACE
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
EOF
    echo 'DAEMON_CONF="/etc/hostapd/hostapd.conf"' > /etc/default/hostapd
fi

if [[ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]]; then
    echo -e "${BLACK}[ INFO ]${NC} Enabling IP forwarding"
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-ip-forward.conf
    echo 1 > /proc/sys/net/ipv4/ip_forward
fi

if ! iptables -t nat -L POSTROUTING -n | grep -q "MASQUERADE.*$INTERNET_IF"; then
    echo -e "${BLACK}[ INFO ]${NC} Configuring firewall"
    iptables -F
    iptables -t nat -F
    iptables -t nat -A POSTROUTING -o "$INTERNET_IF" -j MASQUERADE
    iptables -A FORWARD -i "$INTERNET_IF" -o "$INTERFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    iptables -A FORWARD -i "$INTERFACE" -o "$INTERNET_IF" -j ACCEPT
    iptables -A INPUT -i "$INTERFACE" -j ACCEPT
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4
fi

if ! pgrep dnsmasq &>/dev/null; then
    echo -e "${BLACK}[ INFO ]${NC} Starting dnsmasq"
    dnsmasq --test
    dnsmasq
fi

if ! pgrep hostapd &>/dev/null; then
    echo -e "${BLACK}[ INFO ]${NC} Starting hostapd"
    hostapd /etc/hostapd/hostapd.conf -B
fi

SERVICES_TO_ENABLE=""
systemctl is-enabled --quiet hostapd 2>/dev/null || SERVICES_TO_ENABLE="$SERVICES_TO_ENABLE hostapd"
systemctl is-enabled --quiet dnsmasq 2>/dev/null || SERVICES_TO_ENABLE="$SERVICES_TO_ENABLE dnsmasq"
systemctl is-enabled --quiet netfilter-persistent 2>/dev/null || SERVICES_TO_ENABLE="$SERVICES_TO_ENABLE netfilter-persistent"

if [[ -n "$SERVICES_TO_ENABLE" ]]; then
    echo -e "${BLACK}[ INFO ]${NC} Enabling services"
    systemctl enable $SERVICES_TO_ENABLE
fi

echo -e "${GREEN}[  OK  ]${NC} Hotspot ready!"
{
    echo -e "${YELLOW}SSID:${NC} $SSID"
    echo -e "${YELLOW}Password:${NC} $PASSWORD"
    echo -e "${YELLOW}Channel:${NC} $CHANNEL"
    echo -e "${YELLOW}Hotspot IP:${NC} $HOTSPOT_IP"
    echo -e "${YELLOW}Client IPs:${NC} $DHCP_START - $DHCP_END"
    echo -e "${YELLOW}Internet:${NC} via $INTERNET_IF"
} >> $USERHOME/info.log
