#!/bin/bash
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLACK='\033[1;30m'
CYAN='\033[1;36m'
NC='\033[0m'

[[ -n "$SUDO_USER" ]] && USERNAME="$SUDO_USER" || USERNAME=$(whoami)
[[ -n "$SUDO_USER" ]] && USERHOME=$(eval echo ~$SUDO_USER) || USERHOME="$HOME"

export RED GREEN YELLOW BLACK CYAN NC USERNAME USERHOME

QUIET=false
UNINSTALL=""
INSTALL_TARGETS=""
DETECTED_OS=""
OS_DIR=""
PKG_MANAGER=""

show_help() {
    echo "Usage: $0 [OPTIONS] [TARGETS]"
    echo ""
    echo "Options:"
    echo "  -q, --quiet          Suppress output messages"
    echo "  -u=TARGET            Uninstall specific target but shorter"
    echo "  --uninstall=TARGET   Uninstall specific target"
    echo "  -s, --status         Check status of all services"
    echo "  --status=TARGET      Check status of specific target"
    echo "  -h, --help           Show this help message"
    echo ""
}

detect_os() {
    if grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null || grep -q "raspbian" /etc/os-release 2>/dev/null; then
        DETECTED_OS="raspberry"
        OS_DIR="raspberry"
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        if uname -m | grep -q "x86_64"; then
            DETECTED_OS="fedora"
            OS_DIR="fedora"
            if command -v dnf &>/dev/null; then
                PKG_MANAGER="dnf"
            fi
        else
            echo -e "${RED}[ ERROR ]${NC} Fedora x64 required"
            exit 1
        fi
    elif command -v apt &>/dev/null; then
        if uname -m | grep -q "x86_64"; then
            DETECTED_OS="ubuntu"
            OS_DIR="ubuntu"
            PKG_MANAGER="apt"
        else
            echo -e "${RED}[ ERROR ]${NC} Ubuntu x64 required"
            exit 1
        fi
    else
        echo -e "${RED}[ ERROR ]${NC} Unsupported OS detected - no compatible package manager found"
        exit 1
    fi
}

check_status() {
    local target="$1"
    
    case "$DETECTED_OS" in
        raspberry)
            if [[ "$target" == "all" ]]; then
                for service in hotspot ftp apps bridge; do
                    check_single_status "$service"
                done
            else
                check_single_status "$target"
            fi
            ;;
        ubuntu|fedora)
            if [[ "$target" == "all" ]]; then
                check_single_status "apps"
            else
                check_single_status "$target"
            fi
            ;;
    esac
}

check_single_status() {
    local service="$1"
    
    case "$DETECTED_OS" in
        raspberry)
            case "$service" in
                hotspot)
                    if [ -f ./hotspot.sh ]; then
                        if ./hotspot.sh -s &>/dev/null; then
                            echo -e "${GREEN}[  OK  ]${NC} hotspot service is configured"
                        else
                            echo -e "${RED}[ FAIL ]${NC} hotspot service is not configured"
                        fi
                    else
                        echo -e "${RED}[ FAIL ]${NC} hotspot.sh script not found"
                    fi
                    ;;
                ftp)
                    if [ -f ./ftp.sh ]; then
                        if ./ftp.sh -s &>/dev/null; then
                            echo -e "${GREEN}[  OK  ]${NC} ftp service is configured"
                        else
                            echo -e "${RED}[ FAIL ]${NC} ftp service is not configured"
                        fi
                    else
                        echo -e "${RED}[ FAIL ]${NC} ftp.sh script not found"
                    fi
                    ;;
                apps)
                    if [ -f ./apps.sh ]; then
                        if ./apps.sh -s &>/dev/null; then
                            echo -e "${GREEN}[  OK  ]${NC} apps service is configured"
                        else
                            echo -e "${RED}[ FAIL ]${NC} apps service is not configured"
                        fi
                    else
                        echo -e "${RED}[ FAIL ]${NC} apps.sh script not found"
                    fi
                    ;;
                bridge)
                    if [ -f ./bridges.sh ]; then
                        if ./bridges.sh -s &>/dev/null; then
                            echo -e "${GREEN}[  OK  ]${NC} bridges service is configured"
                        else
                            echo -e "${RED}[ FAIL ]${NC} bridges service is not configured"
                        fi
                    else
                        echo -e "${RED}[ FAIL ]${NC} bridges.sh script not found"
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}[ WARN ]${NC} Unknown service: $service"
                    ;;
            esac
            ;;
        ubuntu|fedora)
            case "$service" in
                apps)
                    if [ -f ./apps.sh ]; then
                        if ./apps.sh -s &>/dev/null; then
                            echo -e "${GREEN}[  OK  ]${NC} apps service is configured"
                        else
                            echo -e "${RED}[ FAIL ]${NC} apps service is not configured"
                        fi
                    else
                        echo -e "${RED}[ FAIL ]${NC} apps.sh script not found"
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}[ WARN ]${NC} Service '$service' not available on $DETECTED_OS"
                    ;;
            esac
            ;;
    esac
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -u=*)
            UNINSTALL="${1#*=}"
            shift
            ;;
        --uninstall=*)
            UNINSTALL="${1#*=}"
            shift
            ;;
        -s|--status)
            TARGET="all"
            if [[ "$1" == -s && $# -gt 1 && "$2" != -* ]]; then
                TARGET="$2"
                shift
            fi
            shift
            
            detect_os
            if [[ ! -d "$OS_DIR" ]]; then
                echo -e "${RED}[ ERROR ]${NC} Directory '$OS_DIR' not found"
                exit 1
            fi
            cd "$OS_DIR"
            check_status "$TARGET"
            exit 0
            ;;
        --status=*)
            TARGET="${1#--status=}"
            shift
            
            detect_os
            if [[ ! -d "$OS_DIR" ]]; then
                echo -e "${RED}[ ERROR ]${NC} Directory '$OS_DIR' not found"
                exit 1
            fi
            cd "$OS_DIR"
            check_status "$TARGET"
            exit 0
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        hotspot|ftp|apps|bridge)
            INSTALL_TARGETS="$INSTALL_TARGETS $1"
            shift
            ;;
        *)
            echo -e "${RED}[ ERROR ]${NC} Unknown option or target: $1"
            show_help
            exit 1
            ;;
    esac
done

detect_os
echo -e "${BLACK}[ INFO ]${NC} Detected OS: $DETECTED_OS"

if [[ -z "$UNINSTALL" && -z "$INSTALL_TARGETS" ]]; then
    case "$DETECTED_OS" in
        raspberry)
            INSTALL_TARGETS="hotspot ftp apps bridge"
            ;;
        ubuntu|fedora)
            INSTALL_TARGETS="apps"
            ;;
    esac
fi

SCRIPT_PATH="$(readlink -f "$0")"

if [[ $EUID -ne 0 ]]; then
    echo -e "${YELLOW}[ WARN ]${NC} Need sudo..."
    ARGS=""
    [[ "$QUIET" == "true" ]] && ARGS="$ARGS -q"
    [[ -n "$UNINSTALL" ]] && ARGS="$ARGS -u=$UNINSTALL"
    [[ -n "$INSTALL_TARGETS" ]] && ARGS="$ARGS $INSTALL_TARGETS"
    sudo "$SCRIPT_PATH" $ARGS
    exit $?
fi

if [[ ! -d "$OS_DIR" ]]; then
    echo -e "${RED}[ ERROR ]${NC} Directory '$OS_DIR' not found"
    exit 1
fi

echo -e "${BLACK}[ INFO ]${NC} Changing to $OS_DIR directory..."
cd "$OS_DIR"

export PKG_MANAGER

if [[ -n "$UNINSTALL" ]]; then
    case "$DETECTED_OS" in
        raspberry)
            case "$UNINSTALL" in
                hotspot)
                    echo -e "${BLACK}[ INFO ]${NC} Uninstalling hotspot..."
                    if [ -f ./hotspot.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./hotspot.sh -u -q
                        else
                            ./hotspot.sh -u
                        fi
                    else
                        echo -e "${RED}[ ERROR ]${NC} hotspot.sh not found"
                        exit 1
                    fi
                    ;;
                ftp)
                    echo -e "${BLACK}[ INFO ]${NC} Uninstalling FTP..."
                    if [ -f ./ftp.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./ftp.sh -u -q
                        else
                            ./ftp.sh -u
                        fi
                    else
                        echo -e "${RED}[ ERROR ]${NC} ftp.sh not found"
                        exit 1
                    fi
                    ;;
                apps)
                    echo -e "${BLACK}[ INFO ]${NC} Uninstalling apps..."
                    if [ -f ./apps.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./apps.sh -u -q
                        else
                            ./apps.sh -u
                        fi
                    else
                        echo -e "${RED}[ ERROR ]${NC} apps.sh not found"
                        exit 1
                    fi
                    ;;
                bridge)
                    echo -e "${BLACK}[ INFO ]${NC} Uninstalling bridges..."
                    if [ -f ./bridges.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./bridges.sh -u -q
                        else
                            ./bridges.sh -u
                        fi
                    else
                        echo -e "${RED}[ ERROR ]${NC} bridges.sh not found"
                        exit 1
                    fi
                    ;;
                *)
                    echo -e "${RED}[ ERROR ]${NC} Invalid uninstall target: $UNINSTALL"
                    exit 1
                    ;;
            esac
            ;;
        ubuntu|fedora)
            case "$UNINSTALL" in
                apps)
                    echo -e "${BLACK}[ INFO ]${NC} Uninstalling apps..."
                    if [ -f ./apps.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./apps.sh -u -q
                        else
                            ./apps.sh -u
                        fi
                    else
                        echo -e "${RED}[ ERROR ]${NC} apps.sh not found"
                        exit 1
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}[ WARN ]${NC} Target '$UNINSTALL' not available on $DETECTED_OS"
                    ;;
            esac
            ;;
    esac
    exit 0
fi

case "$DETECTED_OS" in
    raspberry)
        if ! grep -q "Debian GNU/Linux 11" /etc/os-release; then
            echo -e "${RED}[ ERROR ]${NC} This script requires Debian 11 Bullseye, 12 has issues on my Raspberry Pi"
            exit 1
        fi
        if ! uname -m | grep -q "aarch64\|arm64"; then
            echo -e "${RED}[ ERROR ]${NC} This script requires ARM64 architecture"
            exit 1
        fi
        ;;
    ubuntu)
        if ! grep -q "Ubuntu" /etc/os-release; then
            echo -e "${YELLOW}[ WARN ]${NC} OS release shows non-Ubuntu but apt detected"
        fi
        ;;
    fedora)
        if ! grep -q "Fedora" /etc/os-release; then
            echo -e "${YELLOW}[ WARN ]${NC} OS release shows non-Fedora but dnf detected"
        fi
        ;;
esac

for target in $INSTALL_TARGETS; do
    case "$DETECTED_OS" in
        raspberry)
            case "$target" in
                hotspot)
                    echo -e "${BLACK}[ INFO ]${NC} Installing hotspot..."
                    if [ -f ./hotspot.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./hotspot.sh -q
                        else
                            ./hotspot.sh
                        fi
                    else
                        echo -e "${RED}[ ERROR ]${NC} hotspot.sh not found"
                        exit 1
                    fi
                    ;;
                ftp)
                    echo -e "${BLACK}[ INFO ]${NC} Installing FTP..."
                    if [ -f ./ftp.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./ftp.sh -q
                        else
                            ./ftp.sh
                        fi
                    else
                        echo -e "${YELLOW}[ WARN ]${NC} ftp.sh not found, skipping FTP install"
                    fi
                    ;;
                apps)
                    echo -e "${BLACK}[ INFO ]${NC} Installing apps..."
                    if [ -f ./apps.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./apps.sh -q
                        else
                            ./apps.sh
                        fi
                    else
                        echo -e "${YELLOW}[ WARN ]${NC} apps.sh not found, skipping apps install"
                    fi
                    ;;
                bridge)
                    echo -e "${BLACK}[ INFO ]${NC} Installing bridges..."
                    if [ -f ./bridges.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./bridges.sh -q
                        else
                            ./bridges.sh
                        fi
                    else
                        echo -e "${YELLOW}[ WARN ]${NC} bridges.sh not found, skipping bridge install"
                    fi
                    ;;
            esac
            ;;
        ubuntu|fedora)
            case "$target" in
                apps)
                    echo -e "${BLACK}[ INFO ]${NC} Installing apps..."
                    if [ -f ./apps.sh ]; then
                        if [[ "$QUIET" == "true" ]]; then
                            ./apps.sh -q
                        else
                            ./apps.sh
                        fi
                    else
                        echo -e "${RED}[ ERROR ]${NC} apps.sh not found"
                        exit 1
                    fi
                    ;;
                *)
                    echo -e "${YELLOW}[ WARN ]${NC} Target '$target' not available on $DETECTED_OS"
                    ;;
            esac
            ;;
    esac
done
