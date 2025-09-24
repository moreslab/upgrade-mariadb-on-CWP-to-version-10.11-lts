#!/bin/bash

# ===========================================================
# :                      cwpdb-upgrade.sh
# Description:     This script automates the process of upgrading MariaDB on a CWP server.
# Author:          Dan Kibera
# Email:           info@lintsawa.com
# License:         MIT License
# Version:         1.3
# Date:            4th Oct, 2024
# ===========================================================

# Enhanced color scheme
BOLD="\e[1m"
BLUE="\e[34m"
CYAN="\e[36m"
GREEN="\e[32m"
YELLOW="\e[93m"
RED="\e[91m"
MAGENTA="\e[35m"
RESET="\e[0m"

# ========================
# Variables
# ========================
LOGFILE="/var/log/mariadb_upgrade.log"
BACKUP_BASE_DIR="/home/dbs/databases"
BACKUP_DIR="${BACKUP_BASE_DIR}/backup-$(date +%F_%H-%M-%S)"
TARGET_VERSION="10.11"
DRY_RUN=false
CONFIRM=true
CWP_MYSQL_PASSWORD=$(grep -i 'password' /root/.my.cnf | awk -F'=' '{print $2}' | tr -d ' ')

# ========================
# Functions
# ========================
log_action() {
    local LOG_LEVEL=$1
    local MESSAGE=$2
    local TIMESTAMP=$(date +"%Y-%m-%dT%H:%M:%S")
    echo -e "${TIMESTAMP} [${LOG_LEVEL}] ${MESSAGE}" | tee -a "$LOGFILE"
}

prompt_confirm() {
    if [ "$CONFIRM" = true ]; then
        echo -en "${YELLOW}${BOLD}? ${RESET}${BOLD}$1 (y/n) ${RESET}"
        read -r response
        case "$response" in
            [yY][eE][sS]|[yY]) 
                return 0
                ;;
            *)
                log_action "WARNING" "User aborted the operation"
                exit 1
                ;;
        esac
    fi
}

version_compare() {
    local ver1=$(echo "$1" | awk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }')
    local ver2=$(echo "$2" | awk -F. '{ printf("%03d%03d%03d\n", $1,$2,$3); }')
    [ "$ver1" -lt "$ver2" ] && return 0 || return 1
}

dry_run_notice() {
    if [ "$DRY_RUN" = true ]; then
        log_action "DRY-RUN" "Would execute: $*"
        return 0
    fi
    "$@"
}

configure_mariadb_repo() {
    log_action "INFO" "Configuring MariaDB $TARGET_VERSION repository"
    cat > /etc/yum.repos.d/mariadb.repo <<EOF
[mariadb]
name = MariaDB
baseurl = https://mirror.mariadb.org/yum/$TARGET_VERSION/rhel8-amd64
module_hotfixes=1
gpgkey=https://mirror.mariadb.org/yum/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
}

check_repo_availability() {
    log_action "INFO" "Checking repository availability..."
    if ! curl --output /dev/null --silent --head --fail "https://mirror.mariadb.org/yum/$TARGET_VERSION/rhel8-amd64/repodata/repomd.xml"; then
        log_action "ERROR" "MariaDB $TARGET_VERSION repository not available for AlmaLinux 8"
        exit 1
    fi
}

manage_service() {
    local action=$1
    log_action "INFO" "${action^} MariaDB service"
    if systemctl $action mariadb; then
        log_action "INFO" "Successfully ${action}ed MariaDB"
    else
        log_action "ERROR" "Failed to $action MariaDB"
        [ "$action" = "stop" ] && pkill -9 mysqld
    fi
}

backup_databases() {
    log_action "INFO" "Preparing backup directory..."
    dry_run_notice mkdir -p "$BACKUP_DIR" || { log_action "ERROR" "Backup directory creation failed"; exit 1; }

    log_action "INFO" "Backing up databases..."
    for db in $(mysql -N -e 'SHOW DATABASES' | grep -Ev '(information_schema|oauthv2|performance_schema|mysql|sys)'); do
        log_action "INFO" "Backing up $db"
        dry_run_notice mysqldump --complete-insert --routines --triggers --single-transaction "$db" > "${BACKUP_DIR}/${db}.sql" || {
            log_action "ERROR" "Backup failed for $db"
            exit 1
        }
    done
}

restore_backup() {
    if [ -d "$BACKUP_DIR" ]; then
        log_action "INFO" "Restoring databases from backup..."
        for db_file in "$BACKUP_DIR"/*.sql; do
            dbname=$(basename "$db_file" .sql)
            log_action "INFO" "Restoring $dbname"
            mysql "$dbname" < "$db_file" || log_action "ERROR" "Failed to restore $dbname"
        done
    else
        log_action "ERROR" "Backup directory not found: $BACKUP_DIR"
    fi
}

verify_upgrade() {
    local NEW_VERSION=$(mysql -V | awk '{print $5}' | sed 's/,//')
    local NEW_MAJOR_VERSION=$(echo "$NEW_VERSION" | cut -d. -f1,2)
    
    if [ "$NEW_MAJOR_VERSION" = "$TARGET_VERSION" ]; then
        log_action "INFO" "Successfully upgraded to MariaDB $NEW_VERSION"
        return 0
    else
        log_action "ERROR" "Upgrade failed. Current version: $NEW_VERSION"
        log_action "INFO" "Attempting to restore from backup..."
        restore_backup
        exit 1
    fi
}

test_mariadb() {
    log_action "INFO" "Running post-upgrade test"
    if mysql -e "SELECT VERSION();" &>/dev/null; then
        log_action "INFO" "MariaDB connectivity test passed"
    else
        log_action "ERROR" "MariaDB connectivity test failed"
        exit 1
    fi
}

cleanup() {
    log_action "INFO" "Performing cleanup..."
    dry_run_notice yum clean all
    log_action "INFO" "Cleanup completed"
}

# ========================
# Main Script
# ========================

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -y|--yes)
            CONFIRM=false
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}${BOLD}ERROR:${RESET} This script must be run as root." | tee -a "$LOGFILE" >&2
   exit 1
fi

START_TIME=$(date +%s)

# Header
echo -e "${BOLD}${BLUE}Welcome to the MariaDB Upgrade Script${RESET}"
echo -e "${BOLD}${MAGENTA}==========================================================================${RESET}"
echo -e "${BOLD}${CYAN}                cwpdb-upgrade.sh${RESET}"
echo -e "${BOLD} Description:     This script automates MariaDB upgrade on CWP server${RESET}"
echo -e "${BOLD} Author:          Dan Kibera${RESET}"
echo -e "${BOLD} Email:           info@lintsawa.com${RESET}"
echo -e "${BOLD} Version:         1.3${RESET}"
[ "$DRY_RUN" = true ] && echo -e "${BOLD}${YELLOW}                DRY-RUN MODE${RESET}"
echo -e "${BOLD}${MAGENTA}==========================================================================${RESET}"

log_action "INFO" "Script execution started"
[ "$DRY_RUN" = true ] && log_action "INFO" "Running in dry-run mode - no changes will be made"

# ========================
# Pre-Upgrade Checks
# ========================

# 1. Strict AlmaLinux check
log_action "INFO" "Verifying OS..."
OS_NAME=$(cat /etc/os-release | grep ^ID= | awk -F'=' '{print $2}' | tr -d '"')
OS_VERSION=$(cat /etc/os-release | grep VERSION_ID | awk -F'=' '{print $2}' | tr -d '"')

if [[ "$OS_NAME" != "almalinux" ]]; then
    log_action "ERROR" "Unsupported OS: $OS_NAME. Only AlmaLinux is supported."
    exit 1
fi

if [[ "$OS_VERSION" != "8" && "$OS_VERSION" != "9" ]]; then
    log_action "WARNING" "Untested AlmaLinux version: $OS_VERSION. Proceed with caution."
    prompt_confirm "Continue with unsupported AlmaLinux version?"
fi

# 2. Check MariaDB version
log_action "INFO" "Checking MariaDB version..."
INSTALLED_VERSION=$(mysql -V | awk '{print $5}' | sed 's/,//')
INSTALLED_MAJOR_VERSION=$(echo "$INSTALLED_VERSION" | cut -d. -f1,2)

if version_compare "$INSTALLED_MAJOR_VERSION" "$TARGET_VERSION"; then
    log_action "INFO" "Upgrade needed: $INSTALLED_MAJOR_VERSION -> $TARGET_VERSION"
else
    log_action "INFO" "Current version ($INSTALLED_MAJOR_VERSION) >= target ($TARGET_VERSION). No upgrade needed."
    exit 0
fi

# 3. Disk space check
log_action "INFO" "Checking disk space..."
AVAILABLE_DISK=$(df -BG / | tail -1 | awk '{print $4}' | sed 's/G//')
if [[ "$AVAILABLE_DISK" -lt 10 ]]; then
    log_action "ERROR" "Insufficient disk space (${AVAILABLE_DISK}GB). Minimum 10GB required."
    exit 1
fi

# 4. Check repository availability
check_repo_availability

# ========================
# Upgrade Process
# ========================

prompt_confirm "Proceed with MariaDB upgrade from $INSTALLED_MAJOR_VERSION to $TARGET_VERSION?"

# 1. Backup databases
backup_databases

# 2. Configure repository
configure_mariadb_repo

# 3. Stop MariaDB
manage_service stop

# 4. Remove old packages
log_action "INFO" "Removing old MariaDB packages"
dry_run_notice yum -y remove mariadb-server mariadb-client mariadb-common mysql-common MariaDB*

# 5. Install new version
log_action "INFO" "Installing MariaDB $TARGET_VERSION"
dry_run_notice yum clean all
dry_run_notice yum -y install MariaDB-server MariaDB-client MariaDB-common

# 6. Start MariaDB
manage_service start
manage_service enable

# 7. Run mysql_upgrade
log_action "INFO" "Running mysql_upgrade"
dry_run_notice mysql_upgrade --force

# ========================
# Post-Upgrade
# ========================

# 1. Verify version
verify_upgrade

# 2. Test connectivity
test_mariadb

# 3. Cleanup
cleanup

END_TIME=$(date +%s)
TIME_TAKEN=$((END_TIME - START_TIME))
log_action "INFO" "Upgrade completed in $TIME_TAKEN seconds"

echo -e "${GREEN}${BOLD}MariaDB upgrade to $TARGET_VERSION completed successfully!${RESET}"
[ "$DRY_RUN" = false ] && echo -e "Backups stored in: ${CYAN}$BACKUP_DIR${RESET}"
echo -e "Log file: ${CYAN}$LOGFILE${RESET}" 
