#!/bin/bash

# NTP Home Bridge Installer
# Installs NTP monitoring service for Home Assistant integration
#

set -e

# Append common folders to the PATH
export PATH+=':/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

# Trap any errors
trap abort INT QUIT TERM

######## VARIABLES #########
# NTP Home Bridge directories
NTP_HOME_DIR="/opt/ntphomebridge"
NTP_CONFIG_DIR="/etc/ntphomebridge"
WEB_ROOT="/var/www/html"

# Scripts
NTP_SCRIPTS=("ntpq_crv_sensor.py" "ntpq_pn_sensor.py")

# Dependencies
DEPENDENCIES=("ntp" "python3")
WEB_SERVERS=("lighttpd" "nginx" "apache2")

# Colors
COL_NC='\e[0m'
COL_GREEN='\e[1;32m'
COL_RED='\e[1;31m'
TICK="[${COL_GREEN}✓${COL_NC}]"
CROSS="[${COL_RED}✗${COL_NC}]"
INFO="[i]"

######## FUNCTIONS #########

is_command() {
    command -v "$1" >/dev/null 2>&1
}

package_manager_detect() {
    if is_command apt-get; then
        PKG_MANAGER="apt-get"
        UPDATE_PKG_CACHE="${PKG_MANAGER} update"
        PKG_INSTALL="${PKG_MANAGER} -qq --no-install-recommends install"
    elif is_command yum; then
        PKG_MANAGER="yum"
        PKG_INSTALL="${PKG_MANAGER} install -y"
    else
        printf "  %b No supported package manager found\n" "${CROSS}"
        exit 1
    fi
}

update_package_cache() {
    printf "  %b Updating package cache...\n" "${INFO}"
    if eval "${UPDATE_PKG_CACHE}" &>/dev/null; then
        printf "%b  %b Package cache updated\n" "${OVER}" "${TICK}"
    else
        printf "%b  %b Failed to update package cache\n" "${OVER}" "${CROSS}"
        exit 1
    fi
}

install_dependencies() {
    printf "  %b Installing dependencies...\n" "${INFO}"
    for dep in "${DEPENDENCIES[@]}"; do
        if ! is_command "$dep"; then
            if eval "${PKG_INSTALL} $dep" &>/dev/null; then
                printf "  %b Installed $dep\n" "${TICK}"
            else
                printf "  %b Failed to install $dep\n" "${CROSS}"
                exit 1
            fi
        else
            printf "  %b $dep already installed\n" "${INFO}"
        fi
    done

    # Check for web server
    local web_server_installed=false
    for ws in "${WEB_SERVERS[@]}"; do
        if is_command "$ws"; then
            printf "  %b $ws already installed\n" "${INFO}"
            web_server_installed=true
            break
        fi
    done
    if [[ "$web_server_installed" == false ]]; then
        printf "  %b No web server found, installing lighttpd...\n" "${INFO}"
        if eval "${PKG_INSTALL} lighttpd" &>/dev/null; then
            printf "  %b Installed lighttpd\n" "${TICK}"
        else
            printf "  %b Failed to install lighttpd\n" "${CROSS}"
            exit 1
        fi
    fi
}

create_directories() {
    printf "  %b Creating directories...\n" "${INFO}"
    mkdir -p "$NTP_HOME_DIR"
    mkdir -p "$NTP_CONFIG_DIR"
    mkdir -p "$WEB_ROOT"
    printf "%b  %b Directories created\n" "${OVER}" "${TICK}"
}

copy_scripts() {
    printf "  %b Copying scripts...\n" "${INFO}"
    cp scripts/ntpq_crv_sensor.py "$NTP_HOME_DIR/"
    cp scripts/ntpq_pn_sensor.py "$NTP_HOME_DIR/"
    cp ntp_service.sh "$NTP_HOME_DIR/"
    chmod +x "$NTP_HOME_DIR/ntp_service.sh"
    printf "%b  %b Scripts copied\n" "${OVER}" "${TICK}"
}

setup_systemd_service() {
    printf "  %b Setting up systemd service...\n" "${INFO}"
    cat > /etc/systemd/system/ntphomebridge.service << EOF
[Unit]
Description=NTP Home Bridge Service
After=network.target

[Service]
ExecStart=$NTP_HOME_DIR/ntp_service.sh
WorkingDirectory=$NTP_HOME_DIR/
StandardOutput=journal
StandardError=journal
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable ntphomebridge.service
    printf "%b  %b Systemd service configured\n" "${OVER}" "${TICK}"
}

configure_webserver() {
    printf "  %b Configuring web server...\n" "${INFO}"
    # Detect installed web server
    local web_server=""
    for ws in "${WEB_SERVERS[@]}"; do
        if is_command "$ws"; then
            web_server="$ws"
            break
        fi
    done
    if [[ -n "$web_server" ]]; then
        case "$web_server" in
            lighttpd)
                systemctl enable lighttpd
                systemctl start lighttpd
                ;;
            nginx)
                systemctl enable nginx
                systemctl start nginx
                ;;
            apache2)
                systemctl enable apache2
                systemctl start apache2
                ;;
        esac
        printf "%b  %b $web_server configured\n" "${OVER}" "${TICK}"
    else
        printf "%b  %b No web server found\n" "${OVER}" "${CROSS}"
        exit 1
    fi
}

start_service() {
    printf "  %b Starting NTP Home Bridge service...\n" "${INFO}"
    systemctl start ntphomebridge.service
    printf "%b  %b Service started\n" "${OVER}" "${TICK}"
}

abort() {
    printf "\n%b Installation aborted\n" "${COL_RED}"
    exit 1
}

main() {
    printf "\n%b NTP Home Bridge Installer\n" "${COL_GREEN}"
    printf "==========================\n\n"

    # Check if root
    if [[ $EUID -ne 0 ]]; then
        printf "%b This script must be run as root\n" "${CROSS}"
        exit 1
    fi

    package_manager_detect
    update_package_cache
    install_dependencies
    create_directories
    copy_scripts
    setup_systemd_service
    configure_webserver
    start_service

    printf "\n%b Installation complete!\n" "${TICK}"
    printf "NTP data will be available at http://your_ip/ntpq_crv.json and http://your_ip/ntpq_pn.json\n"
}

main "$@"