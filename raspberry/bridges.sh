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
    echo "  -u, --uninstall  Uninstall this script from the system"
    echo "  -s, --status     Check if the bridges are configured"
    echo "  -h, --help       Show this help message"
    echo ""
}

check_status() {
    local configured=true
    
    if [[ ! -f /etc/systemd/system/bridges.service ]]; then
        configured=false
    fi
    
    if [[ ! -d $USERHOME/data/bridges/tgdc ]]; then
        configured=false
    fi
    
    if [[ ! -d $USERHOME/data/bridges/it ]]; then
        configured=false
    fi
    
    if [[ ! -d $USERHOME/data/bridges/inline ]]; then
        configured=false
    fi
    
    if [[ "$configured" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

uninstall_bridge() {
    echo -e "${BLACK}[ INFO ]${NC} Uninstalling bridges..."
    systemctl stop bridges.service 2>/dev/null || true
    systemctl disable bridges.service 2>/dev/null || true
    rm -f /etc/systemd/system/bridges.service
    systemctl daemon-reload
    mkdir -p $USERHOME/data/secrets
    if [[ -d $USERHOME/data/bridges/tgdc ]]; then
        cp $USERHOME/data/bridges/tgdc/settings.yaml $USERHOME/data/secrets/bridge_settings.yaml
    fi
    if [[ -d $USERHOME/data/bridges/it ]]; then
        cp $USERHOME/data/bridges/it/settings.yaml $USERHOME/data/secrets/it_settings.yaml
    fi
    if [[ -d $USERHOME/data/bridges/msdc ]]; then
        cp $USERHOME/data/bridges/msdc/config.json $USERHOME/data/secrets/messenger_discord_config.json
    fi
    rm -rf $USERHOME/data/bridges
    echo -e "${GREEN}[  OK  ]${NC} Bridges uninstalled successfully"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -u|--uninstall)
            [[ $EUID -ne 0 ]] && { echo -e "${RED}[ ERROR ]${NC} Uninstall requires root privileges"; exit 1; }
            uninstall_bridge
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

echo -e "${BLACK}[ INFO ]${NC} Installing the bridges..."

if ! command -v git &>/dev/null; then
    echo -e "${BLACK}[ INFO ]${NC} Installing git..."
    apt update
    apt install -y git
else
    echo -e "${BLACK}[ INFO ]${NC} git is already installed"
fi

if ! command -v mdatata &>/dev/null; then
    echo -e "${RED}[ ERROR ]${NC} mdata does not exist"
    echo "FAILED: mdata is not installed" >> $USERHOME/info.log
    exit 1
fi

mdata || {
    echo -e "${RED}[ ERROR ]${NC} mdata command failed"
    echo "FAILED: mdata command failed" >> $USERHOME/info.log
    exit 1
}

cd $USERHOME/dev
mkdir -p bridges
cd bridges
if ! [ -e "secrets" ]; then
    echo -e "${RED}[ ERROR ]${NC} Secrets directory does not exist"
    echo "FAILED: Secrets directory does not exist" >> $USERHOME/info.log
    exit 1
fi
git clone https://github.com/TediCross/TediCross tgdc
git clone https://github.com/TediCross/TediCross it
git clone https://github.com/miscord/miscord msdc

mkdir -p $USERHOME/data/bridges/tgdc
mkdir -p $USERHOME/data/bridges/it
mkdir -p $USERHOME/data/bridges/msdc

cp secrets/bridge_settings.yaml $USERHOME/data/bridges/tgdc/settings.yaml
cp secrets/it_settings.yaml $USERHOME/data/bridges/it/settings.yaml
cp secrets/messenger_discord_config.json $USERHOME/data/bridges/msdc/config.json

echo -e "${BLACK}[ INFO ]${NC} Creating bridges service..."
cat > /etc/systemd/system/bridges.service << EOF
[Unit]
Description=Bridge service
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
User=$USERNAME
ExecStart=/bin/bash -c 'tmux new-session -s "it" -d "cd $USERHOME/data/bridges/it && python3 main.py"; tmux new-session -s "tgdc" -d "cd $USERHOME/data/bridges/tgdc && python3 main.py"; tmux new-session -s "inline" -d "cd $USERHOME/data/bots/inline && python3 main.py"'
ExecStop=/bin/bash -c 'tmux send-keys -t it C-c; tmux send-keys -t tgdc C-c; tmux send-keys -t inline C-c; sleep 10; tmux kill-server'

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable bridges.service

echo -e "${GREEN}[  OK  ]${NC} Bridge installation complete!"
