#!/bin/bash
if [[ -z "$RED" || -z "$GREEN" || -z "$YELLOW" || -z "$BLACK" || -z "$CYAN" || -z "$NC" ]]; then
    echo "Not running from install.sh. Please run install.sh."
    exit 1
fi

APPS="git gh"
QUIET=false

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -q, --quiet      Suppress output messages"
    echo "  -u, --uninstall  Uninstall apps configuration"
    echo "  -s, --status     Check if apps are installed (exit 0 if yes, 1 if no)"
    echo "  -h, --help       Show this help message"
    echo ""
}

uninstall_apps() {
    echo -e "${BLACK}[ INFO ]${NC} Uninstalling apps..."
    apt remove --purge -y $APPS 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
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
    if [[ "$configured" == "true" ]]; then
        exit 0
    else
        exit 1
    fi
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

echo -e "${BLACK}[ INFO ]${NC} Installing development apps..."

for app in $APPS; do
    if ! command -v $app &>/dev/null; then
        echo -e "${BLACK}[ INFO ]${NC} Installing $app..."
        apt update
        apt install -y $app
    else
        echo -e "${BLACK}[ INFO ]${NC} $app is already installed"
    fi
done

echo -e "${GREEN}[  OK  ]${NC} Apps installation complete!"
