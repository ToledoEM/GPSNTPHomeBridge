#!/bin/bash

# NTP & GPS Home Bridge Installer
# Installs NTP and GPS monitoring services for Home Assistant integration
#

set -e

# Append common folders to the PATH
export PATH+=':/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

######## VARIABLES #########
VERSION="0.1.0"
REPO_URL="https://github.com/ToledoEM/GPSNTPHomeBridge"  # Updated from placeholder
# NTP & GPS Home Bridge directories
NTP_HOME_DIR="/opt/ntphomebridge"
NTP_CONFIG_DIR="/etc/ntphomebridge"
WEB_ROOT="/var/www/html"

# Dependencies (package name -> binary used to detect it; these differ, e.g.
# the "ntp" package provides "ntpd", so probing for "ntp" would never match)
DEPENDENCIES=("ntp" "python3" "gpsd" "git" "jq")
declare -A DEP_BINARY=(
    [ntp]="ntpd"
    [python3]="python3"
    [gpsd]="gpsd"
    [git]="git"
    [jq]="jq"
)
WEB_SERVERS=("lighttpd" "nginx" "apache2")

# Colors
COL_NC='\e[0m'
COL_GREEN='\e[1;32m'
COL_RED='\e[1;31m'
OVER="\\r\\033[K"
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
        # Probe the binary the package provides, not the package name itself
        local probe="${DEP_BINARY[$dep]:-$dep}"
        if ! is_command "$probe"; then
            if eval "${PKG_INSTALL} $dep" &>/dev/null; then
                printf "  %b Installed %s\n" "${TICK}" "$dep"
            else
                printf "  %b Failed to install %s\n" "${CROSS}" "$dep"
                exit 1
            fi
        else
            printf "  %b %s already installed\n" "${INFO}" "$dep"
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
    
    # Check if we're in the repo directory or need to look elsewhere
    if [[ -f "scripts/ntpq_crv_sensor.py" ]]; then
        SCRIPT_SOURCE="scripts"
    elif [[ -f "/tmp/ntphomebridge-repo/scripts/ntpq_crv_sensor.py" ]]; then
        SCRIPT_SOURCE="/tmp/ntphomebridge-repo/scripts"
    else
        printf "%b  %b Cannot find scripts directory\n" "${OVER}" "${CROSS}"
        exit 1
    fi
    
    cp "$SCRIPT_SOURCE/ntpq_crv_sensor.py" "$NTP_HOME_DIR/"
    cp "$SCRIPT_SOURCE/ntpq_pn_sensor.py" "$NTP_HOME_DIR/"
    cp "$SCRIPT_SOURCE/gps_sensor.py" "$NTP_HOME_DIR/"
    cp "$SCRIPT_SOURCE/ntp_service.sh" "$NTP_HOME_DIR/"
    cp "$SCRIPT_SOURCE/gpsserver.sh" "$NTP_HOME_DIR/"
    chmod +x "$NTP_HOME_DIR/ntp_service.sh"
    chmod +x "$NTP_HOME_DIR/gpsserver.sh"
    chmod +x "$NTP_HOME_DIR/ntpq_crv_sensor.py"
    chmod +x "$NTP_HOME_DIR/ntpq_pn_sensor.py"
    chmod +x "$NTP_HOME_DIR/gps_sensor.py"
    echo "$VERSION" > "$NTP_HOME_DIR/version.txt"
    printf "%b  %b Scripts copied\n" "${OVER}" "${TICK}"
}

setup_ntp_systemd_service() {
    printf "  %b Setting up NTP systemd service...\n" "${INFO}"
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
    printf "%b  %b NTP systemd service configured\n" "${OVER}" "${TICK}"
}

enable_gpsd() {
    printf "  %b Enabling gpsd...\n" "${INFO}"
    # gpsd ships socket-activated on Debian; enable both so the GPS service has
    # something to talk to. Non-fatal: the NTP pipeline works without GPS.
    systemctl enable gpsd.socket &>/dev/null || true
    systemctl enable gpsd &>/dev/null || true
    systemctl start gpsd.socket &>/dev/null || true
    systemctl start gpsd &>/dev/null || true
    printf "%b  %b gpsd enabled\n" "${OVER}" "${TICK}"
    printf "  %b Set the GPS device in /etc/default/gpsd (e.g. DEVICES=\"/dev/ttyAMA0\")\n" "${INFO}"
}

setup_gps_systemd_service() {
    printf "  %b Setting up GPS systemd service...\n" "${INFO}"
    cat > /etc/systemd/system/gpshomebridge.service << EOF
[Unit]
Description=GPS Home Bridge Service
After=network.target gpsd.service

[Service]
ExecStart=$NTP_HOME_DIR/gpsserver.sh
WorkingDirectory=$NTP_HOME_DIR/
StandardOutput=journal
StandardError=journal
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable gpshomebridge.service
    printf "%b  %b GPS systemd service configured\n" "${OVER}" "${TICK}"
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

start_services() {
    printf "  %b Starting NTP Home Bridge service...\n" "${INFO}"
    systemctl start ntphomebridge.service
    printf "%b  %b NTP service started\n" "${OVER}" "${TICK}"

    printf "  %b Starting GPS Home Bridge service...\n" "${INFO}"
    systemctl start gpshomebridge.service
    printf "%b  %b GPS service started\n" "${OVER}" "${TICK}"
}

abort() {
    printf "\n%b Installation aborted\n" "${COL_RED}"
    exit 1
}

# Trap interrupts (declared here: abort must be defined first)
trap abort INT QUIT TERM

main() {
    printf "\n%b NTP & GPS Home Bridge Installer v$VERSION\n" "${COL_GREEN}"
    printf "==========================================\n\n"

    # Check if root
    if [[ $EUID -ne 0 ]]; then
        printf "%b This script must be run as root\n" "${CROSS}"
        exit 1
    fi

    # Check if already installed
    if [[ -d "$NTP_HOME_DIR" ]]; then
        current_version=$(cat "$NTP_HOME_DIR/version.txt" 2>/dev/null || echo "0.0.0")
        if [[ "$current_version" == "$VERSION" ]]; then
            read -p "Already installed with version $VERSION. Reinstall? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 0; fi
        else
            read -p "New version $VERSION available (current $current_version). Update? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 0; fi
        fi
    fi

    # Check if we need to clone repo
    if [[ ! -f "scripts/ntp_service.sh" ]]; then
        printf "  %b Cloning repository...\n" "${INFO}"
        git clone "$REPO_URL" /tmp/ntphomebridge-repo
        cd /tmp/ntphomebridge-repo
    fi

    package_manager_detect
    update_package_cache
    install_dependencies
    create_directories
    copy_scripts
    enable_gpsd
    setup_ntp_systemd_service
    setup_gps_systemd_service
    configure_webserver
    start_services

    # Cleanup
    if [[ -d /tmp/ntphomebridge-repo ]]; then
        rm -rf /tmp/ntphomebridge-repo
    fi

    printf "\n%b Installation complete!\n" "${TICK}"
    printf "NTP and GPS data will be available at http://your_ip/ntpq_crv.json, http://your_ip/ntpq_pn.json, and http://your_ip/gps.json\n"
}

main "$@"