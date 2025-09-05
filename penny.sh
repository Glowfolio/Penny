#!/bin/bash

# Auto-Update Install Script for Linux/Raspberry Pi OS
# This script installs Python, libraries, clones a repo, and sets up auto-update service

set -e  # Exit on any error

# Configuration - MODIFY THESE VARIABLES
GITHUB_REPO="https://github.com/mastermind-mayhem/Penny.git"  # Replace with your repo URL
APP_NAME="penny"                                          # Replace with your app name
INSTALL_DIR="/opt/$APP_NAME"                             # Installation directory
SERVICE_USER="pi"                                        # User to run the service (use 'pi' for Raspberry Pi, or create dedicated user)
UPDATE_INTERVAL="150"                                    # Update check interval in seconds (300 = 5 minutes)

# Python libraries to install (space-separated)
PYTHON_LIBRARIES="requests numpy flask pandas"          # Modify this list as needed

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log "Running as root - OK"
    else
        error "This script must be run as root. Use: sudo $0"
        exit 1
    fi
}

# Detect OS
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
    else
        error "Cannot detect OS version"
        exit 1
    fi
    
    log "Detected OS: $OS $VER"
    
    # Set package manager
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt-get"
        PKG_UPDATE="apt-get update"
        PKG_INSTALL="apt-get install -y"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum update -y"
        PKG_INSTALL="yum install -y"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf update -y"
        PKG_INSTALL="dnf install -y"
    else
        error "No supported package manager found (apt, yum, or dnf)"
        exit 1
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    $PKG_UPDATE
}

# Install Python and dependencies
install_python() {
    log "Installing Python and dependencies..."
    
    if [[ $PKG_MANAGER == "apt-get" ]]; then
        $PKG_INSTALL python3 python3-pip python3-venv git curl wget
    elif [[ $PKG_MANAGER == "yum" ]] || [[ $PKG_MANAGER == "dnf" ]]; then
        $PKG_INSTALL python3 python3-pip python3-venv git curl wget
    fi
    
    # Verify Python installation
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version)
        log "Python installed: $PYTHON_VERSION"
    else
        error "Python installation failed"
        exit 1
    fi
}

# Create application user if it doesn't exist
create_user() {
    if [[ $SERVICE_USER != "root" ]] && ! id "$SERVICE_USER" &>/dev/null; then
        log "Creating user: $SERVICE_USER"
        useradd -r -s /bin/bash -d "$INSTALL_DIR" "$SERVICE_USER"
    fi
}

# Create installation directory
create_directories() {
    log "Creating installation directory: $INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "/var/log/$APP_NAME"
    
    # Set permissions
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
    chown -R "$SERVICE_USER:$SERVICE_USER" "/var/log/$APP_NAME"
}

# Clone or update repository
clone_repo() {
    log "Cloning repository: $GITHUB_REPO"
    
    if [[ -d "$INSTALL_DIR/.git" ]]; then
        warning "Repository already exists, updating..."
        cd "$INSTALL_DIR"
        sudo -u "$SERVICE_USER" git fetch origin
        sudo -u "$SERVICE_USER" git reset --hard origin/main
        sudo -u "$SERVICE_USER" git clean -fd
    else
        # Remove directory if it exists but isn't a git repo
        if [[ -d "$INSTALL_DIR" ]] && [[ ! -d "$INSTALL_DIR/.git" ]]; then
            rm -rf "$INSTALL_DIR"
        fi
        
        sudo -u "$SERVICE_USER" git clone "$GITHUB_REPO" "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        sudo -u "$SERVICE_USER" git checkout main
    fi
    
    log "Repository cloned/updated successfully"
}

# Create virtual environment and install Python libraries
setup_python_env() {
    log "Setting up Python virtual environment..."
    
    cd "$INSTALL_DIR"
    
    # Create virtual environment
    sudo -u "$SERVICE_USER" python3 -m venv venv
    
    # Install libraries
    if [[ -n "$PYTHON_LIBRARIES" ]]; then
        log "Installing Python libraries: $PYTHON_LIBRARIES"
        sudo -u "$SERVICE_USER" ./venv/bin/pip install --upgrade pip
        sudo -u "$SERVICE_USER" ./venv/bin/pip install $PYTHON_LIBRARIES
    fi
    
    # Install from requirements.txt if it exists
    if [[ -f "$INSTALL_DIR/requirements.txt" ]]; then
        log "Installing from requirements.txt"
        sudo -u "$SERVICE_USER" ./venv/bin/pip install -r requirements.txt
    fi
}

# Create update script
create_update_script() {
    log "Creating update script..."
    
    cat > "$INSTALL_DIR/update.sh" << EOF
#!/bin/bash
# Auto-update script for $APP_NAME

cd "$INSTALL_DIR"

# Fetch latest changes
git fetch origin

# Check if there are updates
LOCAL=\$(git rev-parse HEAD)
REMOTE=\$(git rev-parse origin/main)

if [[ "\$LOCAL" != "\$REMOTE" ]]; then
    echo "\$(date): Updates found, pulling changes..."
    
    # Stop the service if running
    systemctl is-active --quiet $APP_NAME && systemctl stop $APP_NAME
    
    # Pull updates
    git reset --hard origin/main
    git clean -fd
    
    # Update Python dependencies if requirements.txt exists
    if [[ -f requirements.txt ]]; then
        ./venv/bin/pip install -r requirements.txt
    fi
    
    # Start the service
    systemctl start $APP_NAME
    
    echo "\$(date): Update completed"
else
    echo "\$(date): No updates available"
fi
EOF
    
    chmod +x "$INSTALL_DIR/update.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/update.sh"
}

# Create systemd service
create_service() {
    log "Creating systemd service..."
    
    # Main application service
    cat > "/etc/systemd/system/$APP_NAME.service" << EOF
[Unit]
Description=$APP_NAME Application
After=network.target
Wants=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin
ExecStart=$INSTALL_DIR/venv/bin/python main.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$APP_NAME

[Install]
WantedBy=multi-user.target
EOF

    # Auto-update service
    cat > "/etc/systemd/system/$APP_NAME-updater.service" << EOF
[Unit]
Description=$APP_NAME Auto Updater
After=network.target

[Service]
Type=oneshot
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/update.sh
StandardOutput=journal
StandardError=journal
EOF

    # Auto-update timer
    cat > "/etc/systemd/system/$APP_NAME-updater.timer" << EOF
[Unit]
Description=Run $APP_NAME updater every $UPDATE_INTERVAL seconds
Requires=$APP_NAME-updater.service

[Timer]
OnBootSec=${UPDATE_INTERVAL}s
OnUnitActiveSec=${UPDATE_INTERVAL}s
Unit=$APP_NAME-updater.service

[Install]
WantedBy=timers.target
EOF

    # Reload systemd and enable services
    systemctl daemon-reload
    systemctl enable "$APP_NAME.service"
    systemctl enable "$APP_NAME-updater.timer"
    
    log "Services created and enabled"
}

# Create management script
create_management_script() {
    log "Creating management script..."
    
    cat > "/usr/local/bin/$APP_NAME" << EOF
#!/bin/bash
# Management script for $APP_NAME

# Validate time format function
validate_time() {
    local time=\$1
    if [[ \$time =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]\$ ]]; then
        return 0
    else
        return 1
    fi
}

case "\$1" in
    start)
        echo "Starting $APP_NAME..."
        systemctl start $APP_NAME
        systemctl start $APP_NAME-updater.timer
        ;;
    stop)
        echo "Stopping $APP_NAME..."
        systemctl stop $APP_NAME
        systemctl stop $APP_NAME-updater.timer
        ;;
    restart)
        echo "Restarting $APP_NAME..."
        systemctl restart $APP_NAME
        ;;
    status)
        systemctl status $APP_NAME
        systemctl status $APP_NAME-updater.timer
        ;;
    logs)
        journalctl -u $APP_NAME -f
        ;;
    update)
        echo "Running manual update..."
        $INSTALL_DIR/update.sh
        ;;
    run)
        if [[ -z "\$2" ]]; then
            echo "Usage: \$0 run <python_file>"
            echo "Example: \$0 run script.py"
            echo "Available Python files in $INSTALL_DIR:"
            find "$INSTALL_DIR" -name "*.py" -type f -printf "  %f\n" 2>/dev/null || echo "  No .py files found"
            exit 1
        fi
        
        PYTHON_FILE="\$2"
        
        # Check if file exists
        if [[ ! -f "$INSTALL_DIR/\$PYTHON_FILE" ]]; then
            echo "Error: Python file '\$PYTHON_FILE' not found in $INSTALL_DIR"
            exit 1
        fi
        
        echo "Running \$PYTHON_FILE as user $SERVICE_USER..."
        cd "$INSTALL_DIR"
        sudo -u "$SERVICE_USER" ./venv/bin/python "\$PYTHON_FILE"
        ;;
    timer)
        if [[ -z "\$2" ]] || [[ -z "\$3" ]] || [[ -z "\$4" ]]; then
            echo "Usage: \$0 timer <create|remove|status|list> <python_file> <time>"
            echo ""
            echo "Commands:"
            echo "  create  - Create and start a new daily timer"
            echo "  remove  - Stop and remove an existing timer"
            echo "  status  - Show status of timer"
            echo "  list    - List all active timers (no additional parameters needed)"
            echo ""
            echo "Time format: HH:MM (24-hour format)"
            echo ""
            echo "Examples:"
            echo "  \$0 timer create backup.py 02:30     # Run backup.py daily at 2:30 AM"
            echo "  \$0 timer create cleanup.py 14:15    # Run cleanup.py daily at 2:15 PM"
            echo "  \$0 timer create report.py 09:00     # Run report.py daily at 9:00 AM"
            echo "  \$0 timer remove backup.py           # Remove backup timer"
            echo "  \$0 timer status backup.py           # Show backup timer status"
            echo "  \$0 timer list                       # List all timers"
            echo ""
            echo "Available Python files in $INSTALL_DIR:"
            find "$INSTALL_DIR" -name "*.py" -type f -printf "  %f\n" 2>/dev/null || echo "  No .py files found"
            exit 1
        fi
        
        ACTION="\$2"
        
        case "\$ACTION" in
            create)
                PYTHON_FILE="\$3"
                TIME="\$4"
                TIMER_NAME="$APP_NAME-\${PYTHON_FILE%.*}"  # Remove .py extension
                
                # Validate python file exists
                if [[ ! -f "$INSTALL_DIR/\$PYTHON_FILE" ]]; then
                    echo "Error: Python file '\$PYTHON_FILE' not found in $INSTALL_DIR"
                    exit 1
                fi
                
                # Validate time format
                if ! validate_time "\$TIME"; then
                    echo "Error: Time must be in HH:MM format (24-hour)"
                    echo "Examples: 09:30, 14:15, 23:59"
                    exit 1
                fi
                
                echo "Creating daily timer for \$PYTHON_FILE at \$TIME..."
                
                # Create service file
                cat > "/etc/systemd/system/\$TIMER_NAME.service" << EOL
[Unit]
Description=$APP_NAME Daily Timer - \$PYTHON_FILE
After=network.target

[Service]
Type=oneshot
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=PATH=$INSTALL_DIR/venv/bin
ExecStart=$INSTALL_DIR/venv/bin/python \$PYTHON_FILE
StandardOutput=journal
StandardError=journal
SyslogIdentifier=\$TIMER_NAME
EOL

                # Create timer file with daily schedule
                cat > "/etc/systemd/system/\$TIMER_NAME.timer" << EOL
[Unit]
Description=Daily Timer for $APP_NAME - \$PYTHON_FILE at \$TIME
Requires=\$TIMER_NAME.service

[Timer]
OnCalendar=*-*-* \$TIME:00
Persistent=true
Unit=\$TIMER_NAME.service

[Install]
WantedBy=timers.target
EOL

                # Reload systemd and enable timer
                systemctl daemon-reload
                systemctl enable "\$TIMER_NAME.timer"
                systemctl start "\$TIMER_NAME.timer"
                
                echo "Daily timer created and started successfully!"
                echo "Script '\$PYTHON_FILE' will run daily at \$TIME"
                echo "Check status with: \$0 timer status \$PYTHON_FILE"
                echo "Check next run time with: systemctl list-timers \$TIMER_NAME.timer"
                ;;
            remove)
                PYTHON_FILE="\$3"
                TIMER_NAME="$APP_NAME-\${PYTHON_FILE%.*}"  # Remove .py extension
                
                echo "Removing timer for \$PYTHON_FILE..."
                
                # Stop and disable timer
                systemctl stop "\$TIMER_NAME.timer" 2>/dev/null || true
                systemctl disable "\$TIMER_NAME.timer" 2>/dev/null || true
                
                # Remove service files
                rm -f "/etc/systemd/system/\$TIMER_NAME.service"
                rm -f "/etc/systemd/system/\$TIMER_NAME.timer"
                
                # Reload systemd
                systemctl daemon-reload
                systemctl reset-failed
                
                echo "Timer removed successfully!"
                ;;
            status)
                PYTHON_FILE="\$3"
                TIMER_NAME="$APP_NAME-\${PYTHON_FILE%.*}"  # Remove .py extension
                
                echo "Status for timer \$TIMER_NAME:"
                if systemctl is-enabled "\$TIMER_NAME.timer" &>/dev/null; then
                    systemctl status "\$TIMER_NAME.timer" --no-pager
                    echo ""
                    echo "Next scheduled runs:"
                    systemctl list-timers "\$TIMER_NAME.timer" --no-pager
                    echo ""
                    echo "Recent execution logs:"
                    journalctl -u "\$TIMER_NAME.service" -n 10 --no-pager 2>/dev/null || echo "No logs found"
                else
                    echo "Timer not found or not enabled"
                fi
                ;;
            list)
                echo "Active $APP_NAME timers:"
                echo "========================="
                
                found_timers=false
                for timer_file in /etc/systemd/system/$APP_NAME-*.timer; do
                    if [[ -f "\$timer_file" ]]; then
                        timer_name=\$(basename "\$timer_file" .timer)
                        script_name="\${timer_name#$APP_NAME-}.py"
                        
                        if systemctl is-enabled "\$timer_name.timer" &>/dev/null; then
                            echo -n "• \$script_name: "
                            
                            # Extract time from timer file
                            if [[ -f "\$timer_file" ]]; then
                                time_schedule=\$(grep "OnCalendar=" "\$timer_file" | cut -d'=' -f2 | cut -d' ' -f2 | cut -d':' -f1,2)
                                if [[ -n "\$time_schedule" ]]; then
                                    echo "Daily at \$time_schedule"
                                else
                                    echo "Schedule unknown"
                                fi
                            else
                                echo "Configuration missing"
                            fi
                            
                            found_timers=true
                        fi
                    fi
                done
                
                if [[ "\$found_timers" == false ]]; then
                    echo "No active timers found."
                    echo ""
                    echo "Create a timer with: \$0 timer create <script.py> <HH:MM>"
                else
                    echo ""
                    echo "Use '\$0 timer status <script.py>' for detailed status"
                    echo "Use 'systemctl list-timers $APP_NAME-*' to see next run times"
                fi
                ;;
            *)
                echo "Invalid timer action. Use: create, remove, status, or list"
                exit 1
                ;;
        esac
        ;;
    uninstall)
        echo "WARNING: This will completely remove $APP_NAME and all its files!"
        echo "Python will remain installed on the system."
        read -p "Are you sure you want to continue? (yes/no): " confirm
        
        if [[ "\$confirm" == "yes" ]]; then
            echo "Uninstalling $APP_NAME..."
            
            # Stop and disable main services
            systemctl stop $APP_NAME 2>/dev/null || true
            systemctl stop $APP_NAME-updater.timer 2>/dev/null || true
            systemctl disable $APP_NAME 2>/dev/null || true
            systemctl disable $APP_NAME-updater.timer 2>/dev/null || true
            
            # Find and remove all custom timers
            for timer_file in /etc/systemd/system/$APP_NAME-*.timer; do
                if [[ -f "\$timer_file" ]]; then
                    timer_name=\$(basename "\$timer_file")
                    service_name="\${timer_name%.timer}.service"
                    echo "Removing timer: \$timer_name"
                    systemctl stop "\$timer_name" 2>/dev/null || true
                    systemctl disable "\$timer_name" 2>/dev/null || true
                    rm -f "\$timer_file"
                    rm -f "/etc/systemd/system/\$service_name"
                fi
            done
            
            # Remove main service files
            rm -f /etc/systemd/system/$APP_NAME.service
            rm -f /etc/systemd/system/$APP_NAME-updater.service
            rm -f /etc/systemd/system/$APP_NAME-updater.timer
            
            # Reload systemd
            systemctl daemon-reload
            systemctl reset-failed
            
            # Remove application directory
            if [[ -d "$INSTALL_DIR" ]]; then
                echo "Removing application directory: $INSTALL_DIR"
                rm -rf "$INSTALL_DIR"
            fi
            
            # Remove log directory
            if [[ -d "/var/log/$APP_NAME" ]]; then
                echo "Removing log directory: /var/log/$APP_NAME"
                rm -rf "/var/log/$APP_NAME"
            fi
            
            # Remove user if it was created by the installer (not pi, root, or system users)
            if [[ "$SERVICE_USER" != "pi" ]] && [[ "$SERVICE_USER" != "root" ]] && id "$SERVICE_USER" &>/dev/null; then
                echo "Removing user: $SERVICE_USER"
                userdel "$SERVICE_USER" 2>/dev/null || true
            fi
            
            # Remove this management script
            rm -f "/usr/local/bin/$APP_NAME"
            
            echo "$APP_NAME has been completely uninstalled."
            echo "Python and system packages remain installed."
        else
            echo "Uninstall cancelled."
        fi
        ;;
    *)
        echo "Usage: \$0 {start|stop|restart|status|logs|update|run|timer|uninstall}"
        echo ""
        echo "Commands:"
        echo "  start         - Start the main application and auto-updater"
        echo "  stop          - Stop the main application and auto-updater"
        echo "  restart       - Restart the main application"
        echo "  status        - Show status of services"
        echo "  logs          - Show live logs"
        echo "  update        - Run manual update from repository"
        echo "  run <file>    - Run a Python file directly"
        echo "  timer         - Manage daily scheduled Python script timers"
        echo "  uninstall     - Remove everything (keeps Python)"
        exit 1
        ;;
esac
EOF
    
    chmod +x "/usr/local/bin/$APP_NAME"
    log "Management script created: $APP_NAME"
}

# Main installation function
main() {
    log "Starting installation of $APP_NAME..."
    
    check_root
    detect_os
    update_system
    install_python
    create_user
    create_directories
    clone_repo
    setup_python_env
    create_update_script
    create_service
    create_management_script
    
    log "Installation completed successfully!"
    info ""
    info "The application will automatically check for updates every $UPDATE_INTERVAL seconds"
    info "Installation directory: $INSTALL_DIR"
    info "Log files: journalctl -u $APP_NAME"
}

# Run main function
main "$@"