#!/bin/bash
#
# install.sh - Installation script for Vision Sensor Web App
#
# Purpose:
#   Installs vision-sensor web app with interactive configuration prompts
#   and systemd service setup for Raspberry Pi deployment.
#
# Usage:
#   sudo ./install.sh
#
# Exit Codes:
#   0 - Installation successful
#   1 - Invalid input or missing prerequisites
#

set -euo pipefail

# ============================================================================
# Global Variables
# ============================================================================

INSTALL_DIR="/opt/vision-sensor"
SYSTEMD_DIR="/etc/systemd/system"
ENV_FILE="$INSTALL_DIR/.envrc"
APP_USER="vision-sensor"
REBOOT_REQUIRED=false

# Configuration variables
HOSTNAME=""
ADMIN_USERNAME=""
ADMIN_PASSWORD=""
FLASK_SECRET_KEY=""

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo "[INFO] $*"
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

# Show progress dots while a command runs
run_with_progress() {
    local description="$1"
    local command="$2"

    # Run command in background
    eval "$command" > /tmp/install_progress.log 2>&1 &
    local pid=$!

    # Show progress dots while command runs
    echo -n "[INFO] $description"
    while kill -0 $pid 2>/dev/null; do
        echo -n "."
        sleep 0.5
    done

    # Wait for command to complete
    wait $pid
    local exit_code=$?

    # Cleanup
    cat /tmp/install_progress.log >> /tmp/vision_sensor_install.log 2>/dev/null || true
    rm -f /tmp/install_progress.log

    # Finish the line
    echo ""

    return $exit_code
}

# ============================================================================
# Prerequisite Checks
# ============================================================================

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check root privileges
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi

    # Check systemd
    if ! command -v systemctl &> /dev/null; then
        log_error "systemd is not available"
        exit 1
    fi

    log_info "✓ All prerequisites met"
}

# ============================================================================
# Interactive Prompts
# ============================================================================

prompt_configuration() {
    echo ""
    echo "=========================================="
    echo "  Vision Sensor Installation"
    echo "=========================================="
    echo ""
    echo "This script will install the Vision Sensor web app."
    echo ""

    # Hostname
    log_info "Device hostname for easy identification on the network"
    local default_hostname="vision-sensor-$(date +%s | tail -c 5)"
    echo ""
    read -p "Enter hostname [default: $default_hostname]: " HOSTNAME
    HOSTNAME=${HOSTNAME:-$default_hostname}

    # Validate hostname (lowercase alphanumeric and hyphens only)
    if ! [[ "$HOSTNAME" =~ ^[a-z0-9-]+$ ]]; then
        log_error "Invalid hostname. Must contain only lowercase letters, numbers, and hyphens."
        exit 1
    fi

    # Admin Username
    echo ""
    log_info "Admin login credentials for the web portal"
    read -p "Enter admin username [default: admin]: " ADMIN_USERNAME
    ADMIN_USERNAME=${ADMIN_USERNAME:-admin}

    # Validate username (alphanumeric and underscore only)
    if ! [[ "$ADMIN_USERNAME" =~ ^[a-zA-Z0-9_]+$ ]]; then
        log_error "Invalid username. Must contain only letters, numbers, and underscores."
        exit 1
    fi

    # Admin Password
    echo ""
    read -s -p "Enter admin password [default: admin123]: " ADMIN_PASSWORD
    echo ""  # newline after password input

    # Use default if empty
    ADMIN_PASSWORD=${ADMIN_PASSWORD:-admin123}

    # Validate password (minimum 6 characters)
    if [ ${#ADMIN_PASSWORD} -lt 6 ]; then
        log_error "Password must be at least 6 characters long"
        exit 1
    fi

    # Confirm password
    echo ""
    read -s -p "Confirm admin password: " password_confirm
    echo ""

    if [ "$ADMIN_PASSWORD" != "$password_confirm" ]; then
        log_error "Passwords do not match"
        exit 1
    fi

    # Auto-generate Flask secret key
    log_info "Generating Flask secret key..."
    FLASK_SECRET_KEY=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
    log_info "✓ Secret key generated"

    # Display configuration summary
    echo ""
    echo "=========================================="
    echo "  Configuration Summary"
    echo "=========================================="
    echo "Hostname: $HOSTNAME"
    echo "Install Directory: $INSTALL_DIR"
    echo "Service User: $APP_USER"
    echo "Admin Username: $ADMIN_USERNAME"
    echo "Admin Password: ********"
    echo "Flask Secret Key: ${FLASK_SECRET_KEY:0:16}... (auto-generated)"
    echo "=========================================="
    echo ""

    read -p "Proceed with installation? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log_info "Installation cancelled by user"
        exit 0
    fi
}

# ============================================================================
# System Package Installation
# ============================================================================

install_system_packages() {
    log_info "Installing system dependencies..."

    local packages="python3 python3-pip python3-opencv curl modemmanager network-manager i2c-tools python3-smbus"

    if run_with_progress "Installing system packages" "apt-get update -qq && apt-get install -y -qq $packages"; then
        log_info "✓ System packages installed"
    else
        log_error "Failed to install system packages"
        log_error "See /tmp/vision_sensor_install.log for details"
        exit 1
    fi
}

# ============================================================================
# Poetry Installation
# ============================================================================

install_poetry() {
    log_info "Installing Poetry package manager..."

    # Check if Poetry is already installed
    if command -v poetry &> /dev/null; then
        log_info "✓ Poetry already installed"
        return 0
    fi

    # Install Poetry
    if curl -sSL https://install.python-poetry.org | python3 - 2>&1 | tee -a /tmp/vision_sensor_install.log; then
        log_info "✓ Poetry installed"

        # Add Poetry to PATH for current session
        export PATH="$HOME/.local/bin:$PATH"

        # Verify installation
        if command -v poetry &> /dev/null; then
            log_info "✓ Poetry available: $(poetry --version)"
        else
            log_warn "Poetry installed but not in PATH"
            log_warn "Add to PATH: export PATH=\"\$HOME/.local/bin:\$PATH\""
        fi
    else
        log_error "Failed to install Poetry"
        exit 1
    fi
}

# ============================================================================
# User and Directory Creation
# ============================================================================

create_user_and_directories() {
    log_info "Creating user and directories..."

    # Create group if not exists
    if ! getent group $APP_USER > /dev/null 2>&1; then
        groupadd -r $APP_USER
        log_info "✓ Created $APP_USER group"
    else
        log_info "✓ $APP_USER group already exists"
    fi

    # Create user if not exists
    if ! id $APP_USER > /dev/null 2>&1; then
        useradd -r -g $APP_USER -s /usr/sbin/nologin -d "$INSTALL_DIR" $APP_USER
        # Add user to video group for camera access
        usermod -a -G video $APP_USER
        log_info "✓ Created $APP_USER user"
    else
        log_info "✓ $APP_USER user already exists"
        # Ensure user is in video group
        usermod -a -G video $APP_USER 2>/dev/null || true
    fi

    # Create installation directory
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
        log_info "✓ Created $INSTALL_DIR"
    fi

    # Set ownership
    chown -R $APP_USER:$APP_USER "$INSTALL_DIR"
    chmod 755 "$INSTALL_DIR"
    log_info "✓ Set directory ownership and permissions"
}

# ============================================================================
# Application Installation
# ============================================================================

install_application() {
    log_info "Installing application files..."

    # Get the script directory (assuming script is in scripts/ subdirectory)
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_dir="$(dirname "$script_dir")"

    # Copy application files
    cp -r "$project_dir"/* "$INSTALL_DIR/"

    # Set ownership
    chown -R $APP_USER:$APP_USER "$INSTALL_DIR"

    log_info "✓ Application files copied"

    # Install Python dependencies using Poetry
    log_info "Installing Python dependencies with Poetry..."

    cd "$INSTALL_DIR"

    # Ensure poetry is available
    export PATH="$HOME/.local/bin:$PATH"

    # Configure Poetry to create virtualenv in project directory
    /root/.local/bin/poetry config virtualenvs.in-project true

    # Remove any existing cached virtualenvs to force creation in project directory
    /root/.local/bin/poetry env remove --all 2>/dev/null || true

    # Install dependencies as root, then fix ownership
    # (vision-sensor user doesn't have access to /root/.local/bin/poetry)
    if /root/.local/bin/poetry install 2>&1 | tee -a /tmp/vision_sensor_install.log; then
        log_info "✓ Python dependencies installed"

        # Fix ownership of .venv directory
        if [ -d "$INSTALL_DIR/.venv" ]; then
            chown -R $APP_USER:$APP_USER "$INSTALL_DIR/.venv"
            log_info "✓ Virtual environment ownership set"
        fi
    else
        log_error "Failed to install Python dependencies"
        log_error "Check /tmp/vision_sensor_install.log for details"
        exit 1
    fi

    cd - > /dev/null
}

# ============================================================================
# Environment File Creation
# ============================================================================

create_env_file() {
    log_info "Creating environment configuration file..."

    # Create .envrc file with configuration
    # Note: systemd EnvironmentFile doesn't support 'export' keyword
    # Use plain KEY=value format
    cat > "$ENV_FILE" <<EOF
# Flask Configuration
FLASK_SECRET_KEY=$FLASK_SECRET_KEY
FLASK_ENV=production
FLASK_DEBUG=False

# Server Configuration
HOST=0.0.0.0
PORT=5000

# Default User Credentials
DEFAULT_USERNAME=$ADMIN_USERNAME
DEFAULT_PASSWORD=$ADMIN_PASSWORD

# Camera Configuration
CAMERA_INDEX=0
CAMERA_WIDTH=640
CAMERA_HEIGHT=480
CAMERA_FPS=15
JPEG_QUALITY=80
EOF

    # Set secure permissions
    chmod 600 "$ENV_FILE"
    chown $APP_USER:$APP_USER "$ENV_FILE"

    log_info "✓ Environment file created at $ENV_FILE"
    log_info "  Flask Secret Key: ${FLASK_SECRET_KEY:0:16}..."
    log_info "  Admin Username: $ADMIN_USERNAME"
    log_info "  Admin Password: ********"
}

# ============================================================================
# Hostname Configuration
# ============================================================================

configure_hostname() {
    log_info "Configuring device hostname..."

    local current_hostname=$(hostname)

    # Skip if hostname hasn't changed
    if [ "$current_hostname" = "$HOSTNAME" ]; then
        log_info "✓ Hostname already set to: $HOSTNAME"
        return 0
    fi

    # Update /etc/hostname
    log_info "Setting hostname to: $HOSTNAME"
    echo "$HOSTNAME" > /etc/hostname

    # Update /etc/hosts
    if grep -q "127.0.1.1" /etc/hosts; then
        sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
    else
        echo "127.0.1.1	$HOSTNAME" >> /etc/hosts
    fi

    # Set hostname immediately
    if command -v hostnamectl &> /dev/null; then
        hostnamectl set-hostname "$HOSTNAME"
    else
        hostname "$HOSTNAME"
    fi

    log_info "✓ Hostname changed to '$HOSTNAME'"
    REBOOT_REQUIRED=true
}

# ============================================================================
# 4G Modem Configuration
# ============================================================================

configure_4g_modem() {
    log_info "Configuring 4G cellular modem..."

    # Enable and start services
    log_info "Enabling ModemManager and NetworkManager..."
    if systemctl enable ModemManager NetworkManager 2>/dev/null && \
       systemctl start ModemManager NetworkManager 2>/dev/null; then
        log_info "✓ Modem services enabled"
    else
        log_warn "Failed to enable modem services"
        return 0  # Non-fatal
    fi

    # Wait for ModemManager to detect modem
    log_info "Waiting for modem detection (10 seconds)..."
    sleep 10

    # Check if modem is detected
    if ! mmcli -L 2>/dev/null | grep -q "Modem"; then
        log_warn "No modem detected - may initialize after reboot"
        log_warn "Check with: mmcli -L"
        return 0  # Non-fatal
    fi

    log_info "✓ Modem detected"

    # Remove old cellular connection if exists
    if nmcli c show cellular &>/dev/null; then
        log_info "Removing old cellular configuration..."
        nmcli c delete cellular 2>/dev/null || true
    fi

    # Add GSM connection with US Cellular APN
    log_info "Creating cellular connection..."
    if nmcli c add type gsm ifname cdc-wdm0 con-name cellular gsm.apn "uscc00000.enterprise0.usc-cdp" 2>/dev/null; then
        log_info "✓ Cellular connection created"
    else
        log_warn "Failed to create cellular connection"
        return 0  # Non-fatal
    fi

    # Enable autoconnect
    nmcli c modify cellular connection.autoconnect yes 2>/dev/null || true

    # Activate connection
    log_info "Activating cellular connection..."
    if nmcli c up cellular 2>/dev/null; then
        log_info "✓ Cellular connection activated"

        # Wait and check interface
        sleep 5
        if ip addr show wwan0 &>/dev/null; then
            local wwan_ip=$(ip -4 addr show wwan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
            if [ -n "$wwan_ip" ]; then
                log_info "✓ Cellular active with IP: $wwan_ip"
            fi
        fi
    else
        log_warn "Cellular connection may activate after reboot"
    fi
}

# ============================================================================
# WittyPi Configuration
# ============================================================================

configure_wittypi() {
    log_info "Installing and configuring WittyPi 4 Mini..."

    # Non-fatal error handling pattern - log warnings and continue
    local wittypi_dir="/opt/wittypi"
    local wittypi_url="https://www.uugear.com/repo/WittyPi4/install.sh"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local original_dir=$(pwd)

    # Enable I2C interface via raspi-config
    log_info "Enabling I2C interface..."
    if raspi-config nonint do_i2c 0 2>&1 | tee -a /tmp/vision_sensor_install.log; then
        log_info "✓ I2C interface enabled"
    else
        log_warn "Failed to enable I2C interface - may need manual configuration"
        return 0
    fi

    # Verify /dev/i2c-1 exists after enablement (may require reboot)
    if [ -c /dev/i2c-1 ]; then
        log_info "✓ I2C device /dev/i2c-1 detected"
    else
        log_warn "I2C device not yet available - will activate after reboot"
        REBOOT_REQUIRED=true
    fi

    # Create installation directory
    if [ ! -d "$wittypi_dir" ]; then
        mkdir -p "$wittypi_dir"
        log_info "Created WittyPi installation directory: $wittypi_dir"
    fi

    # Change to installation directory
    cd "$wittypi_dir" || {
        log_warn "Failed to access WittyPi installation directory"
        return 0  # Non-fatal
    }

    # Download WittyPi 4 installation script
    log_info "Downloading WittyPi 4 software..."
    if ! wget -q "$wittypi_url" -O install.sh; then
        log_warn "Failed to download WittyPi installation script"
        cd "$original_dir"
        return 0  # Non-fatal
    fi

    # Run installation script
    log_info "Running WittyPi installation script (this may take a few minutes)..."
    if sh install.sh 2>&1 | tee /tmp/wittypi_install.log; then
        log_info "✓ WittyPi software installed to $wittypi_dir"
    else
        log_warn "WittyPi installation encountered errors - check /tmp/wittypi_install.log"
    fi

    # Return to original directory
    cd "$original_dir"

    # Verify installation
    if [ ! -f "$wittypi_dir/wittypi/utilities.sh" ]; then
        log_warn "WittyPi software not found at $wittypi_dir/wittypi"
        log_warn "Skipping WittyPi configuration"
        return 0  # Non-fatal
    fi

    log_info "✓ WittyPi installed at: $wittypi_dir/wittypi"

    # Re-enable NTP service (WittyPi installation may have disabled it)
    log_info "Re-enabling NTP for network time synchronization..."
    if timedatectl set-ntp true 2>/dev/null; then
        log_info "✓ NTP service enabled"
    else
        log_warn "Could not enable NTP service"
    fi

    # Install wittypi-firstboot.service
    log_info "Installing WittyPi first-boot configuration service..."
    if [ -f "$script_dir/templates/wittypi-firstboot.service" ]; then
        cp "$script_dir/templates/wittypi-firstboot.service" "$SYSTEMD_DIR/"
        chmod 644 "$SYSTEMD_DIR/wittypi-firstboot.service"
        systemctl daemon-reload
        if systemctl enable wittypi-firstboot.service 2>/dev/null; then
            log_info "✓ WittyPi first-boot configuration service enabled"
            log_info "  Service will run after reboot to configure auto-boot and RTC"
        else
            log_warn "Could not enable wittypi-firstboot service"
        fi
    else
        log_warn "wittypi-firstboot.service template not found"
    fi

    # Install RTC sync services
    log_info "Installing RTC synchronization services..."

    # Install shutdown sync service
    if [ -f "$script_dir/templates/wittypi-rtc-sync.service" ]; then
        cp "$script_dir/templates/wittypi-rtc-sync.service" "$SYSTEMD_DIR/"
        chmod 644 "$SYSTEMD_DIR/wittypi-rtc-sync.service"
    fi

    # Install daily sync timer and service
    if [ -f "$script_dir/templates/wittypi-rtc-sync.timer" ]; then
        cp "$script_dir/templates/wittypi-rtc-sync.timer" "$SYSTEMD_DIR/"
        chmod 644 "$SYSTEMD_DIR/wittypi-rtc-sync.timer"
    fi

    if [ -f "$script_dir/templates/wittypi-rtc-sync-daily.service" ]; then
        cp "$script_dir/templates/wittypi-rtc-sync-daily.service" "$SYSTEMD_DIR/"
        chmod 644 "$SYSTEMD_DIR/wittypi-rtc-sync-daily.service"
    fi

    # Reload and enable RTC sync services
    systemctl daemon-reload

    if systemctl enable wittypi-rtc-sync.service 2>/dev/null; then
        log_info "✓ RTC sync on shutdown enabled"
    else
        log_warn "Could not enable RTC sync on shutdown"
    fi

    if systemctl enable wittypi-rtc-sync.timer 2>/dev/null; then
        log_info "✓ Daily RTC sync timer enabled"
    else
        log_warn "Could not enable daily RTC sync timer"
    fi

    # Install power schedule
    log_info "Installing WittyPi power schedule..."

    if [ -f "$script_dir/templates/daily_7am_to_930pm.wpi" ]; then
        # Ensure schedules directory exists
        mkdir -p "$wittypi_dir/wittypi/schedules"

        # Copy as template
        cp "$script_dir/templates/daily_7am_to_930pm.wpi" "$wittypi_dir/wittypi/schedules/"
        chmod 755 "$wittypi_dir/wittypi/schedules/daily_7am_to_930pm.wpi"
        log_info "✓ Copied schedule template to $wittypi_dir/wittypi/schedules/"

        # Copy as active schedule
        cp "$script_dir/templates/daily_7am_to_930pm.wpi" "$wittypi_dir/wittypi/schedule.wpi"
        chmod 755 "$wittypi_dir/wittypi/schedule.wpi"
        log_info "✓ Installed as active schedule: schedule.wpi"

        # Process the schedule
        if [ -f "$wittypi_dir/wittypi/runScript.sh" ]; then
            log_info "Processing power schedule..."
            cd "$wittypi_dir/wittypi" || log_warn "Could not change to WittyPi directory"

            if bash runScript.sh >> schedule.log 2>&1; then
                log_info "✓ Power schedule processed"
                log_info "  Schedule: 7:00 AM to 9:30 PM daily (local time)"

                # Verify schedule by checking log
                if grep -q "7:00\|07:00" schedule.log 2>/dev/null && grep -q "21:30\|9:30" schedule.log 2>/dev/null; then
                    log_info "✓ Schedule verification passed (7:00 AM and 9:30 PM times found)"
                else
                    log_warn "Schedule processing may need verification - check schedule.log"
                fi
            else
                log_warn "Failed to process power schedule - check $wittypi_dir/wittypi/schedule.log"
            fi

            cd "$original_dir"
        else
            log_warn "runScript.sh not found - schedule not processed"
        fi
    else
        log_warn "Power schedule file not found at $script_dir/templates/daily_7am_to_930pm.wpi"
        log_info "  Power schedule can be configured manually later"
    fi

    # Set reboot required flag
    REBOOT_REQUIRED=true
    log_info "✓ WittyPi configuration complete"
    log_info "  Reboot required to activate I2C and first-boot configuration"

    return 0
}

# ============================================================================
# Power Monitor Installation
# ============================================================================

install_power_monitor() {
    log_info "Installing power monitoring service..."

    # Non-fatal error handling pattern - log warnings and continue
    local power_monitor_dir="/opt/power-monitor"
    local data_dir="/var/log/power_daily"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Create power monitor directory
    if [ ! -d "$power_monitor_dir" ]; then
        mkdir -p "$power_monitor_dir"
        log_info "✓ Created power monitor directory: $power_monitor_dir"
    fi

    # Create data directory for power logs
    if [ ! -d "$data_dir" ]; then
        mkdir -p "$data_dir"
        chmod 755 "$data_dir"
        log_info "✓ Created power data directory: $data_dir"
    fi

    # Copy monitoring script
    if [ -f "$script_dir/templates/witty_pi_monitor.sh" ]; then
        cp "$script_dir/templates/witty_pi_monitor.sh" "$power_monitor_dir/"
        chmod 755 "$power_monitor_dir/witty_pi_monitor.sh"
        chown root:root "$power_monitor_dir/witty_pi_monitor.sh"
        log_info "✓ Installed witty_pi_monitor.sh to $power_monitor_dir/"
    else
        log_warn "witty_pi_monitor.sh not found - skipping power monitoring installation"
        return 0  # Non-fatal
    fi

    # Verify python3-smbus is available (already installed in install_system_packages)
    if ! python3 -c "import smbus" 2>/dev/null; then
        log_warn "python3-smbus not available - battery voltage monitoring may not work"
        log_warn "This should have been installed earlier. Manual installation: sudo apt install python3-smbus"
    else
        log_info "✓ python3-smbus available for INA219 battery monitoring"
    fi

    # Copy systemd service file
    if [ -f "$script_dir/templates/power-monitor.service" ]; then
        cp "$script_dir/templates/power-monitor.service" "$SYSTEMD_DIR/"
        chmod 644 "$SYSTEMD_DIR/power-monitor.service"
        chown root:root "$SYSTEMD_DIR/power-monitor.service"
        log_info "✓ Installed power-monitor.service"
    else
        log_warn "power-monitor.service template not found - skipping service installation"
        return 0  # Non-fatal
    fi

    # Reload systemd and enable service
    systemctl daemon-reload

    if systemctl enable power-monitor.service 2>/dev/null; then
        log_info "✓ Power monitor service enabled"
    else
        log_warn "Failed to enable power-monitor service"
        return 0  # Non-fatal
    fi

    # Start the service
    if systemctl start power-monitor.service 2>/dev/null; then
        log_info "✓ Power monitor service started"

        # Wait a moment and check status
        sleep 2
        if systemctl is-active power-monitor.service &>/dev/null; then
            log_info "✓ Power monitor is running"
            log_info "  Data will be logged to $data_dir/"
        else
            log_warn "Power monitor service started but may not be active"
            log_warn "This is normal if WittyPi hardware is not yet connected"
            log_warn "Check logs with: sudo journalctl -u power-monitor -n 50"
        fi
    else
        log_warn "Failed to start power-monitor service"
        log_warn "Service requires WittyPi hardware to be connected"
        log_warn "Service will auto-start after reboot if hardware is available"
    fi

    log_info "✓ Power monitoring configuration complete"
    return 0
}

# ============================================================================
# systemd Service Installation
# ============================================================================

install_systemd_service() {
    log_info "Creating systemd service..."

    # Create service file
    # Note: Using .venv/bin/python3 directly instead of 'poetry run'
    # because poetry is in /root/.local/bin which vision-sensor user can't access
    cat > "$SYSTEMD_DIR/vision-sensor.service" <<EOF
[Unit]
Description=Vision Sensor Web App
After=network.target

[Service]
Type=simple
User=$APP_USER
Group=$APP_USER
WorkingDirectory=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$INSTALL_DIR/.venv/bin/python3 app.py
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    chmod 644 "$SYSTEMD_DIR/vision-sensor.service"
    log_info "✓ Service file created"

    # Reload systemd
    systemctl daemon-reload

    # Enable service
    systemctl enable vision-sensor.service
    log_info "✓ Service enabled"

    # Start service
    systemctl start vision-sensor.service
    log_info "✓ Service started"

    # Check status
    sleep 2
    if systemctl is-active vision-sensor.service &>/dev/null; then
        log_info "✓ Service is running"
    else
        log_warn "Service failed to start"
        log_warn "Check logs: sudo journalctl -u vision-sensor -n 50"
    fi
}

# ============================================================================
# Installation Summary
# ============================================================================

display_summary() {
    local service_status=$(systemctl is-active vision-sensor.service 2>/dev/null || echo "stopped")
    local hostname=$(hostname)
    local wwan_ip=$(ip -4 addr show wwan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || echo "")
    local eth_ip=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || echo "")
    local wlan_ip=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1 || echo "")

    # WittyPi status
    local wittypi_status="Not Installed"
    local firstboot_status="N/A"
    local rtc_sync_status="N/A"
    local schedule_status="N/A"

    if [ -d "/opt/wittypi/wittypi" ]; then
        wittypi_status="Installed"
        firstboot_status=$(systemctl is-enabled wittypi-firstboot.service 2>/dev/null || echo "Not configured")
        rtc_sync_status=$(systemctl is-enabled wittypi-rtc-sync.timer 2>/dev/null || echo "Not configured")
        if [ -f "/opt/wittypi/wittypi/schedule.wpi" ]; then
            schedule_status="Installed"
        else
            schedule_status="Not configured"
        fi
    fi

    # Power monitor status
    local power_monitor_status="Not Installed"
    local power_monitor_service="N/A"
    if [ -f "/opt/power-monitor/witty_pi_monitor.sh" ]; then
        power_monitor_status="Installed"
        power_monitor_service=$(systemctl is-active power-monitor.service 2>/dev/null || echo "inactive")
    fi

    echo ""
    echo "=========================================="
    echo "  Vision Sensor Installation Complete"
    echo "=========================================="
    echo ""
    echo "Hostname: $hostname"
    echo "Installation Directory: $INSTALL_DIR"
    echo "Service Status: $service_status"
    echo ""
    echo "WittyPi 4 Mini:"
    echo "  Installation: $wittypi_status"
    echo "  First-Boot Config: $firstboot_status"
    echo "  RTC Sync Timer: $rtc_sync_status"
    echo "  Power Schedule: $schedule_status"
    echo ""
    echo "Power Monitor:"
    echo "  Installation: $power_monitor_status"
    echo "  Service Status: $power_monitor_service"
    if [ -d "/var/log/power_daily" ]; then
        echo "  Data Directory: /var/log/power_daily"
    fi
    echo ""
    echo "Network Addresses:"
    [ -n "$eth_ip" ] && echo "  Ethernet (eth0): http://$eth_ip:5000"
    [ -n "$wlan_ip" ] && echo "  WiFi (wlan0): http://$wlan_ip:5000"
    [ -n "$wwan_ip" ] && echo "  Cellular (wwan0): http://$wwan_ip:5000"
    echo ""
    echo "Login Credentials:"
    echo "  Username: $ADMIN_USERNAME"
    echo "  Password: ********"
    echo "  (Configured in $ENV_FILE)"
    echo ""
    echo "Service Management:"
    echo "  Status:  sudo systemctl status vision-sensor"
    echo "  Start:   sudo systemctl start vision-sensor"
    echo "  Stop:    sudo systemctl stop vision-sensor"
    echo "  Restart: sudo systemctl restart vision-sensor"
    echo "  Logs:    sudo journalctl -u vision-sensor -f"
    echo ""

    if [ "$REBOOT_REQUIRED" = true ]; then
        echo "⚠️  REBOOT REQUIRED"
        echo "  WittyPi I2C configuration requires reboot:"
        echo "  sudo reboot"
        echo ""
    fi

    echo "=========================================="
    echo ""
}

# ============================================================================
# Main Installation
# ============================================================================

main() {
    log_info "Vision Sensor Installation Starting..."

    # Check prerequisites
    check_prerequisites

    # Prompt for configuration
    prompt_configuration

    # Install system packages
    install_system_packages

    # Install Poetry
    install_poetry

    # Create user and directories
    create_user_and_directories

    # Install application
    install_application

    # Create environment file
    create_env_file

    # Configure hostname
    configure_hostname

    # Configure 4G modem
    configure_4g_modem

    # Configure WittyPi power management
    configure_wittypi

    # Install power monitoring service
    install_power_monitor

    # Install systemd service
    install_systemd_service

    # Display summary
    display_summary

    log_info "Installation complete!"
    exit 0
}

# Run main
main "$@"
