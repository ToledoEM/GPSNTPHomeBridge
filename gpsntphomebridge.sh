#!/bin/bash

# NTP & GPS Home Bridge Installer
# Installs NTP and GPS monitoring services for Home Assistant integration
#

set -e

# Append common folders to the PATH
export PATH+=':/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'

######## VARIABLES #########
VERSION="0.2.0"
REPO_URL="https://github.com/ToledoEM/GPSNTPHomeBridge"  # Updated from placeholder
# NTP & GPS Home Bridge directories
NTP_HOME_DIR="/opt/ntphomebridge"
NTP_CONFIG_DIR="/etc/ntphomebridge"
WEB_ROOT="/var/www/html"
NTP_SERVER="ntpd"

# Dependencies (package name -> binary used to detect it; these differ, e.g.
# the "ntp" package provides "ntpd", so probing for "ntp" would never match)
DEPENDENCIES=("python3" "gpsd" "git" "jq")
declare -A DEP_BINARY=(
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

get_ip() {
    ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for (i = 1; i <= NF; i++) if ($i == "src") { print $(i + 1); exit }}'
}

# Messages go in as %s arguments, never into the format string, so a path or
# value containing % or \ is printed as-is.
log() {
    printf "  %b %s\n" "$2" "$1"
}

log_info() {
    log "$1" "${INFO}"
}

log_tick() {
    log "$1" "${TICK}"
}

log_cross() {
    log "$1" "${CROSS}"
}

log_over() {
    printf "%b  %b %s\n" "${OVER}" "$2" "$1"
}

log_tick_over() {
    log_over "$1" "${TICK}"
}

log_cross_over() {
    log_over "$1" "${CROSS}"
}

usage() {
    cat << EOF
Usage: $0 [--full|--bridge-only|--uninstall] [--ntp-server ntpd|chronyd]
       [--web-root DIR] [--skip-gpsd]

The bridge is a pair of small services that read your NTP daemon (ntpd or
chrony) and gpsd, and publish the readings as JSON files for Home Assistant.

Run in a terminal without a mode flag to pick the mode from a menu. Without a
terminal (piped, scripted) the default is --full.

  --full                     Install the NTP daemon, gpsd, a web server and the
                             bridge. For a machine with nothing set up yet.
  --bridge-only              Install only the bridge scripts and their systemd
                             services, for a machine where the NTP daemon, gpsd
                             and a web server already run. Missing dependencies
                             are listed and installed only if you agree.
  --uninstall                Remove the bridge services, scripts and JSON files.
                             Packages are left installed.
  --ntp-server ntpd|chronyd  NTP daemon to report on (default: ntpd; with
                             --bridge-only, the one found on the machine).
                             On apt systems installing chrony removes ntp.
  --web-root DIR             Directory the JSON files are published to
                             (default: /var/www/html). Point it at a directory
                             your web server already serves.
  --skip-gpsd                With --full: do not enable or start gpsd (for
                             existing setups). gpsd is still installed if missing.
  -h, --help                 Show this help.
EOF
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
        log_over "No supported package manager found" "${CROSS}"
        exit 1
    fi
}

update_package_cache() {
    log_info "Updating package cache..."
    if eval "${UPDATE_PKG_CACHE}" &>/dev/null; then
        log_over "Package cache updated" "${TICK}"
    else
        log_over "Failed to update package cache" "${CROSS}"
        exit 1
    fi
}

install_dependencies() {
    log_info "Installing dependencies..."

    # Set up for our specified NTP server
    case "$NTP_SERVER" in
        ntpd)
            DEP_BINARY[ntp]="ntpd"
            DEPENDENCIES+=("ntp")
            ;;
        chronyd)
            DEP_BINARY[chrony]="chronyd"
            DEPENDENCIES+=("chrony")
            if is_command ntpd && ! is_command chronyd; then
                log_info "ntpd found: installing chrony will replace it"
            fi
            ;;
    esac

    # Loop packages to install missing binaries if needed
    for dep in "${DEPENDENCIES[@]}"; do
        # Probe the binary the package provides, not the package name itself
        local probe="${DEP_BINARY[$dep]:-$dep}"
        if ! is_command "$probe"; then
            log_info "Installing $dep..."
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
            log_info "$ws already installed"
            web_server_installed=true
            break
        fi
    done
    if [[ "$web_server_installed" == false ]]; then
        log_info "No web server found, installing lighttpd..."
        if eval "${PKG_INSTALL} lighttpd" &>/dev/null; then
            log_tick "Installed lighttpd"
        else
            log_cross "Failed to install lighttpd"
            exit 1
        fi
    fi
}

create_directories() {
    log_info "Creating directories..."
    mkdir -p "$NTP_HOME_DIR"
    mkdir -p "$NTP_CONFIG_DIR"
    mkdir -p "$WEB_ROOT"
    log_tick_over "Directories created"
}

copy_scripts() {
    log_info "Copying scripts..."
    
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
    cp "$SCRIPT_SOURCE/ntp_service_ntpd.sh" "$NTP_HOME_DIR/"
    cp "$SCRIPT_SOURCE/ntp_service_chronyd.sh" "$NTP_HOME_DIR/"
    cp "$SCRIPT_SOURCE/gpsserver.sh" "$NTP_HOME_DIR/"
    chmod +x "$NTP_HOME_DIR/ntp_service_ntpd.sh"
    chmod +x "$NTP_HOME_DIR/ntp_service_chronyd.sh"
    chmod +x "$NTP_HOME_DIR/gpsserver.sh"
    chmod +x "$NTP_HOME_DIR/ntpq_crv_sensor.py"
    chmod +x "$NTP_HOME_DIR/ntpq_pn_sensor.py"
    chmod +x "$NTP_HOME_DIR/gps_sensor.py"
    echo "$VERSION" > "$NTP_HOME_DIR/version.txt"
    log_tick_over "Scripts copied"
}

configure_env() {
    log_info "Configuring environment file..."
    # %q quotes the value so a path with spaces survives being sourced
    printf 'WEB_ROOT=%q\n' "$WEB_ROOT" > "$NTP_CONFIG_DIR/bridge.env"
    log_tick_over "Environment file written"
}

setup_ntp_systemd_service() {
    log_info "Setting up NTP systemd service for $NTP_SERVER..."

    BINARY="ntp_service_${NTP_SERVER}.sh"

    # Link the binary to ntp_service.sh to maintain compatibility
    ln -sfn "$NTP_HOME_DIR/$BINARY" "$NTP_HOME_DIR/ntp_service.sh"

    cat > /etc/systemd/system/ntphomebridge.service << EOF
[Unit]
Description=NTP Home Bridge Service
After=network.target

[Service]
ExecStart=$NTP_HOME_DIR/$BINARY
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
    log_tick_over "NTP systemd service configured"
}

enable_gpsd() {
    log_info "Enabling gpsd..."
    # gpsd ships socket-activated on Debian; enable both so the GPS service has
    # something to talk to. Non-fatal: the NTP pipeline works without GPS.
    systemctl enable gpsd.socket &>/dev/null || true
    systemctl enable gpsd &>/dev/null || true
    systemctl start gpsd.socket &>/dev/null || true
    systemctl start gpsd &>/dev/null || true
    log_tick_over "gpsd enabled"
    log_info "Set the GPS device in /etc/default/gpsd (e.g. DEVICES=\"/dev/ttyAMA0\")"
}

setup_gps_systemd_service() {
    log_info "Setting up GPS systemd service..."
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
    log_tick_over "GPS systemd service configured"
}

configure_webserver() {
    log_info "Configuring web server..."
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
        log_tick_over "$web_server configured"
    else
        log_cross_over "No web server found"
        exit 1
    fi
}

start_services() {
    log_info "Starting NTP Home Bridge service..."
    systemctl restart ntphomebridge.service
    log_tick_over "NTP service started"

    log_info "Starting GPS Home Bridge service..."
    systemctl restart gpshomebridge.service
    log_tick_over "GPS service started"
}

print_banner() {
    printf "\n%b NTP & GPS Home Bridge Installer v$VERSION\n" "${COL_GREEN}"
    printf "==========================================\n\n%b" "${OVER}"
}

######## MODE MENU #########

MENU_ITEMS=("Full install" "Bridge only" "Uninstall" "Quit")
MENU_MODES=("full" "bridge" "uninstall" "quit")
# One description per menu item, shown while the item is highlighted.
# Keep lines to 60 characters so they stay inside the intro text's width.
MENU_DESC=(
"For a fresh Pi with nothing set up yet.
Installs and enables: NTP daemon (ntpd, or chrony with
--ntp-server chronyd), gpsd, python3, jq, git, and
lighttpd if no web server is present. Then the bridge.
On Debian, installing chrony removes ntp and vice versa."
"For machines where ntpd or chrony, gpsd and a web server
are already installed and configured.
Installs: bridge scripts in /opt/ntphomebridge, config in
/etc/ntphomebridge and two systemd services.
Leaves alone: NTP daemon, gpsd and web server settings.
Missing dependencies are listed and you are asked first."
"Stops and removes the two bridge services,
/opt/ntphomebridge, /etc/ntphomebridge and the three JSON
files in the web root.
Does not remove ntp, chrony, gpsd, the web server or any
other package. A cleanup hint is printed at the end."
"Leave without changing anything."
)

# The menu needs a real terminal on both ends and a working tput
menu_available() {
    [ -t 0 ] && [ -t 1 ] && is_command tput && tput cols >/dev/null 2>&1
}

menu_restore_terminal() {
    tput cnorm 2>/dev/null || true
    tput sgr0 2>/dev/null || true
}

# Draw the description of menu item $1 starting at screen row $2
menu_draw_description() {
    local idx="$1" row="$2" line bar="|"
    if [[ "$(locale charmap 2>/dev/null)" == "UTF-8" ]]; then
        bar="▌"
    fi
    # A yellow bar down the left edge marks the block; the text keeps the
    # terminal's own colour so it reads on dark and light backgrounds.
    bar="$(tput setaf 3)${bar}$(tput sgr0)"

    tput cup "$row" 0
    tput ed
    printf "  %s %s%s%s\n" "$bar" "$(tput bold)" "${MENU_ITEMS[$idx]}" "$(tput sgr0)"
    while IFS= read -r line; do
        printf "  %s %s\n" "$bar" "$line"
    done <<< "${MENU_DESC[$idx]}"
    printf "\n  Up/Down or 1-%d to move, Enter to select, q to quit" "${#MENU_ITEMS[@]}"
}

# Sets MODE from the user's pick. Nothing is installed or removed here.
show_menu() {
    local sel=0 count=${#MENU_ITEMS[@]} key rest i
    local first_row=8
    # Centres the options under the 65-column intro text that starts at column 2
    local menu_col=26

    tput civis
    clear
    tput setaf 2
    tput cup 1 2; printf "NTP & GPS Home Bridge v%s" "$VERSION"
    tput sgr0
    tput cup 3 2; printf "The bridge is a pair of small services that read your NTP daemon"
    tput cup 4 2; printf "(ntpd or chrony) and gpsd, and publish the readings as JSON files"
    tput cup 5 2; printf "for Home Assistant. It does not keep time or read the GPS itself."

    while true; do
        for ((i = 0; i < count; i++)); do
            tput cup $((first_row + i)) "$menu_col"
            if [[ $i -eq $sel ]]; then
                tput rev
                printf "> %d. %-14s" $((i + 1)) "${MENU_ITEMS[$i]}"
                tput sgr0
            else
                printf "  %d. %-14s" $((i + 1)) "${MENU_ITEMS[$i]}"
            fi
        done
        menu_draw_description "$sel" $((first_row + count + 1))

        # EOF on stdin: leave without changing anything
        IFS= read -rsn1 key || { sel=$((count - 1)); break; }
        case "$key" in
            $'\e')
                # Arrow keys arrive as ESC [ A / ESC [ B
                rest=""
                IFS= read -rsn2 -t 0.1 rest || true
                case "$rest" in
                    '[A') sel=$(((sel + count - 1) % count)) ;;
                    '[B') sel=$(((sel + 1) % count)) ;;
                esac
                ;;
            [1-9])
                if [[ $key -le $count ]]; then sel=$((key - 1)); fi
                ;;
            q|Q)
                sel=$((count - 1))
                break
                ;;
            '')
                break
                ;;
        esac
    done

    menu_restore_terminal
    clear
    MODE="${MENU_MODES[$sel]}"
    if [[ "$MODE" == "quit" ]]; then
        exit 0
    fi
}

######## BRIDGE ONLY #########

# Pick the NTP daemon already on the machine when --ntp-server was not given
detect_ntp_server() {
    local has_chrony=0 has_ntpd=0
    if is_command chronyc; then has_chrony=1; fi
    if is_command ntpq; then has_ntpd=1; fi

    if [[ $has_chrony -eq 1 && $has_ntpd -eq 1 ]]; then
        # Both present: report on the one that is running
        if systemctl is-active --quiet chronyd 2>/dev/null \
                || systemctl is-active --quiet chrony 2>/dev/null; then
            NTP_SERVER="chronyd"
        else
            NTP_SERVER="ntpd"
        fi
    elif [[ $has_chrony -eq 1 ]]; then
        NTP_SERVER="chronyd"
    else
        # ntpd, or neither: the dependency check reports what is missing
        NTP_SERVER="ntpd"
    fi
}

# Bridge-only installs nothing unasked. List what is missing and let the user
# decide; without the required tools the bridge cannot run, so stop there.
check_bridge_dependencies() {
    local required=() optional=() dep ws web_server_installed=false

    is_command python3 || required+=("python3")
    is_command jq || required+=("jq")
    case "$NTP_SERVER" in
        ntpd) is_command ntpq || required+=("ntp") ;;
        chronyd) is_command chronyc || required+=("chrony") ;;
    esac
    # git is only needed to fetch the scripts when they are not next to us
    if [[ ! -f "scripts/ntp_service_ntpd.sh" ]]; then
        is_command git || required+=("git")
    fi

    # Without these the NTP endpoints still work, so they do not block
    is_command gpsd || optional+=("gpsd")
    for ws in "${WEB_SERVERS[@]}"; do
        if is_command "$ws"; then
            web_server_installed=true
            break
        fi
    done
    if [[ "$web_server_installed" == false ]]; then
        optional+=("lighttpd")
    fi

    if [[ ${#required[@]} -eq 0 && ${#optional[@]} -eq 0 ]]; then
        log_tick "All dependencies present"
        return 0
    fi

    log_info "Missing dependencies:"
    for dep in "${required[@]}"; do
        printf "      %s (required)\n" "$dep"
    done
    for dep in "${optional[@]}"; do
        case "$dep" in
            gpsd) printf "      %s (needed for the GPS endpoint)\n" "$dep" ;;
            lighttpd) printf "      %s (no lighttpd, nginx or apache2 found to serve %s)\n" "$dep" "$WEB_ROOT" ;;
        esac
    done

    read -p "Install the missing packages? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        package_manager_detect
        update_package_cache
        for dep in "${required[@]}" "${optional[@]}"; do
            log_info "Installing $dep..."
            if eval "${PKG_INSTALL} $dep" &>/dev/null; then
                log_tick "Installed $dep"
            else
                log_cross "Failed to install $dep"
                exit 1
            fi
        done
    elif [[ ${#required[@]} -gt 0 ]]; then
        log_cross "Cannot continue without: ${required[*]}"
        exit 1
    else
        log_info "Continuing without: ${optional[*]}"
    fi
}

######## UNINSTALL #########

uninstall() {
    local unit_dir="/etc/systemd/system" unit f

    if [[ ! -d "$NTP_HOME_DIR" && ! -d "$NTP_CONFIG_DIR" \
            && ! -f "$unit_dir/ntphomebridge.service" \
            && ! -f "$unit_dir/gpshomebridge.service" ]]; then
        log_info "NTP & GPS Home Bridge is not installed, nothing to remove"
        exit 0
    fi

    read -p "Remove the NTP & GPS Home Bridge services, scripts and JSON files? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 0; fi

    # The JSON files live wherever the install put them; read that before the
    # config directory goes. --web-root overrides.
    if [[ "$WEB_ROOT_SET" -eq 0 && -f "$NTP_CONFIG_DIR/bridge.env" ]]; then
        # shellcheck source=/dev/null
        WEB_ROOT=$(. "$NTP_CONFIG_DIR/bridge.env" 2>/dev/null; printf '%s' "$WEB_ROOT")
    fi

    log_info "Stopping services..."
    for unit in ntphomebridge.service gpshomebridge.service; do
        systemctl stop "$unit" &>/dev/null || true
        systemctl disable "$unit" &>/dev/null || true
        rm -f "$unit_dir/$unit"
    done
    systemctl daemon-reload &>/dev/null || true
    log_tick_over "Services stopped and removed"

    log_info "Removing files..."
    rm -rf "$NTP_HOME_DIR" "$NTP_CONFIG_DIR"
    for f in ntpq_crv.json ntpq_pn.json gps.json; do
        rm -f "$WEB_ROOT/$f" "$WEB_ROOT/$f.tmp"
    done
    log_tick_over "Removed $NTP_HOME_DIR, $NTP_CONFIG_DIR and the JSON files in $WEB_ROOT"

    printf "\n%b Uninstall complete\n\n" "${TICK}"
    log_info "No packages were removed. The installer may have added ntp or chrony,"
    log_info "gpsd, lighttpd, jq and git. If nothing else on this machine uses them,"
    log_info "remove the ones you no longer need, for example:"
    if is_command apt-get; then
        printf "      sudo apt-get remove gpsd lighttpd jq\n"
        printf "      sudo apt-get autoremove\n"
    elif is_command yum; then
        printf "      sudo yum remove gpsd lighttpd jq\n"
        printf "      sudo yum autoremove\n"
    else
        printf "      use your package manager to remove them\n"
    fi
}

abort() {
    menu_restore_terminal
    printf "\n%b Installation aborted\n" "${COL_RED}"
    exit 1
}

# Trap interrupts (declared here: abort must be defined first)
trap abort INT QUIT TERM

main() {
    print_banner

    # Parse flags before the root check so --help works for any user
    SKIP_GPSD=0
    MODE=""
    NTP_SERVER_SET=0
    WEB_ROOT_SET=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --full)
                MODE="full"
                ;;
            --bridge-only)
                MODE="bridge"
                ;;
            --uninstall)
                MODE="uninstall"
                ;;
            --skip-gpsd)
                SKIP_GPSD=1
                ;;
            --ntp-server)
                [ -n "$2" ] || { log_cross_over "--ntp-server needs a value" >&2; usage >&2; exit 1; }
                NTP_SERVER="$2"
                NTP_SERVER_SET=1
                shift
                ;;
            --web-root)
                [ -n "$2" ] || { log_cross_over "--web-root needs a value" >&2; usage >&2; exit 1; }
                WEB_ROOT="$2"
                WEB_ROOT_SET=1
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_cross_over "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
        shift
    done

    case "$NTP_SERVER" in
        ntpd|chronyd)
            ;;
        ntp)
            NTP_SERVER=ntpd
            ;;
        chrony)
            NTP_SERVER=chronyd
            ;;
        *)
            log_cross_over "Invalid --ntp-server value: $NTP_SERVER (expected ntpd or chronyd)" >&2
            usage >&2
            exit 1
            ;;
    esac

    # Check if root
    if [[ $EUID -ne 0 ]]; then
        printf "%b This script must be run as root\n" "${CROSS}"
        exit 1
    fi

    # No mode flag: ask in a terminal, otherwise keep the historic behaviour
    # (full install) so piped and scripted runs do not change.
    if [[ -z "$MODE" ]]; then
        if menu_available; then
            show_menu
            print_banner
        else
            MODE="full"
        fi
    fi

    if [[ "$MODE" == "uninstall" ]]; then
        uninstall
        exit 0
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

    # Fetch the collection scripts when the installer is run on its own, as it
    # is when downloaded directly. git may not be present on a minimal image,
    # so sort out dependencies first.
    if [[ "$MODE" == "full" ]]; then
        package_manager_detect
        update_package_cache
        install_dependencies
    else
        if [[ "$NTP_SERVER_SET" -eq 0 ]]; then
            detect_ntp_server
        fi
        log_info "Bridge only: reporting on $NTP_SERVER, server side left as it is"
        check_bridge_dependencies
    fi

    if [[ ! -f "scripts/ntp_service_ntpd.sh" ]]; then
        log_info "Cloning repository..."
        rm -rf /tmp/ntphomebridge-repo
        if ! git clone --depth 1 "$REPO_URL" /tmp/ntphomebridge-repo; then
            printf "  %b Failed to clone %s\n" "${CROSS}" "$REPO_URL"
            exit 1
        fi
        cd /tmp/ntphomebridge-repo
    fi

    create_directories
    copy_scripts

    if [[ "$MODE" == "full" && "$SKIP_GPSD" -eq 0 ]]; then
        enable_gpsd
    fi

    configure_env
    setup_ntp_systemd_service
    setup_gps_systemd_service
    if [[ "$MODE" == "full" ]]; then
        configure_webserver
    fi
    start_services

    # Cleanup
    if [[ -d /tmp/ntphomebridge-repo ]]; then
        rm -rf /tmp/ntphomebridge-repo
    fi

    SERVER_IP=$(get_ip)

    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="<your ip>"
    fi

    printf "\n%b Installation complete!\n" "${TICK}"
    printf "NTP and GPS data will be available at http://%s/ntpq_crv.json, http://%s/ntpq_pn.json, and http://%s/gps.json\n" \
        "$SERVER_IP" "$SERVER_IP" "$SERVER_IP"
    if [[ "$MODE" == "bridge" ]]; then
        printf "The files are written to %s. Make sure your web server serves that directory.\n" "$WEB_ROOT"
    fi
}

main "$@"