#!/bin/bash
if [[ -z "$RED" || -z "$GREEN" || -z "$YELLOW" || -z "$BLACK" || -z "$CYAN" || -z "$NC" ]]; then
    echo "Not running from install.sh. Please run install.sh."
    exit 1
fi

APPS="git gh tmux"
UTILS="macchanger myip checknetwork mdata fixnpm fixpy"
QUIET=false

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -q, --quiet      Suppress output messages"
    echo "  -u, --uninstall  Uninstall this script from the system"
    echo "  -s, --status     Check if apps are installed"
    echo "  -h, --help       Show this help message"
    echo ""
}

uninstall_apps() {
    echo -e "${BLACK}[ INFO ]${NC} Uninstalling apps..."
    apt remove --purge -y git gh 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    for util in $UTILS; do
        rm -f "/usr/local/bin/$util"
    done
    echo -e "${GREEN}[  OK  ]${NC} Apps uninstalled successfully"
}

check_status() {
    local configured=true
    for app in $APPS; do
        if ! command -v $app &>/dev/null; then
            configured=false
            break
        fi
    done
    for util in $UTILS; do
        if [[ ! -f /usr/local/bin/$util ]]; then
            configured=false
            break
        fi
    done
    if [[ "$configured" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
}

install_packages() {
    url="$1"
    tmpdeb="/tmp/$(basename "$url")"
    wget -q "$url" -O "$tmpdeb"
    apt install -y "$tmpdeb"
    rm -f "$tmpdeb"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -u|--uninstall)
            [[ $EUID -ne 0 ]] && { echo -e "${RED}[ ERROR ]${NC} Uninstall requires root privileges"; exit 1; }
            uninstall_apps
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

if ! command -v git &>/dev/null; then
    echo -e "${BLACK}[ INFO ]${NC} Installing git..."
    apt update
    apt install -y git
else
    echo -e "${BLACK}[ INFO ]${NC} git is already installed"
fi

if ! command -v gh &>/dev/null; then
    echo -e "${BLACK}[ INFO ]${NC} Installing Github CLI for ARM64..."
    version=2.74.2
    install_packages "https://github.com/cli/cli/releases/download/v${version}/gh_${version}_linux_arm64.deb"
else
    echo -e "${BLACK}[ INFO ]${NC} gh is already installed"
fi

for util in $UTILS; do
    if [[ -f "./$util" ]]; then
        echo -e "${BLACK}[ INFO ]${NC} Copying $util to /usr/local/bin/"
        cp "./$util" "/usr/local/bin/$util"
        chmod +x "/usr/local/bin/$util"
    else
        echo -e "${YELLOW}[ WARN ]${NC} $util not found in current directory, skipping"
    fi
done

echo -e "${GREEN}[  OK  ]${NC} Apps installation complete!"
