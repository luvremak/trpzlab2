#!/usr/bin/env bash
#
# mywebapp — automated installation script (single entry point).
#
# Individual variant: N = 11  ->  V2 = 2, V3 = 3, V5 = 2
#   V2 = 2 : configuration via a config file (/etc/mywebapp/config.toml), PostgreSQL
#   V3 = 3 : Simple Inventory application
#   V5 = 2 : application listens on port 5200
#
# Target OS: Ubuntu Server 24.04 LTS
# Must be run as root:  sudo ./install.sh
#
# The script is idempotent — it can be re-run safely.
#
set -euo pipefail

# --------------------------------------------------------------------------
# Parameters
# --------------------------------------------------------------------------
GRADEBOOK_NUMBER=11               # N — the number the variant is derived from

APP_NAME="mywebapp"
APP_HOST="127.0.0.1"
APP_PORT=5200                     # V5 = 2
APP_DIR="/opt/mywebapp"
APP_USER="app"

CONFIG_DIR="/etc/mywebapp"
CONFIG_FILE="${CONFIG_DIR}/config.toml"

DB_NAME="mywebapp"
DB_USER="mywebapp"
DB_HOST="127.0.0.1"
DB_PORT=5432

DEFAULT_OS_USER="ubuntu"          # the cloud-image default user to lock
DEFAULT_LOGIN_PASSWORD="12345678" # default password for teacher and operator

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

log() { echo; echo "[install] $*"; }

# --------------------------------------------------------------------------
# Pre-flight checks
# --------------------------------------------------------------------------
if [[ "${EUID}" -ne 0 ]]; then
    echo "This script must be run as root: sudo $0" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# 1. Install the required system packages
# --------------------------------------------------------------------------
install_packages() {
    log "Installing system packages (python3-venv, postgresql, nginx)..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        python3 python3-venv python3-pip \
        postgresql \
        nginx \
        openssl
}

# --------------------------------------------------------------------------
# 2. Create the system and login users
# --------------------------------------------------------------------------
create_users() {
    log "Creating users (app, student, teacher, operator)..."

    # app — system user the application runs as; minimal privileges, no login.
    if ! id "${APP_USER}" &>/dev/null; then
        useradd --system --no-create-home --shell /usr/sbin/nologin "${APP_USER}"
    fi

    # student — the project owner; administrative rights via the sudo group.
    if ! id student &>/dev/null; then
        useradd --create-home --shell /bin/bash student
    fi
    usermod -aG sudo student
    # Let "student" log in over SSH with the same key as the default user,
    # because the default user is locked at the end of this script.
    if [[ -f "/home/${DEFAULT_OS_USER}/.ssh/authorized_keys" ]]; then
        install -d -m 700 -o student -g student /home/student/.ssh
        install -m 600 -o student -g student \
            "/home/${DEFAULT_OS_USER}/.ssh/authorized_keys" \
            /home/student/.ssh/authorized_keys
    fi

    # teacher — reviewer account; administrative rights, default password that
    # must be changed at first login.
    if ! id teacher &>/dev/null; then
        useradd --create-home --shell /bin/bash teacher
    fi
    usermod -aG sudo teacher
    echo "teacher:${DEFAULT_LOGIN_PASSWORD}" | chpasswd
    chage -d 0 teacher

    # operator — limited service management via sudo; default password that
    # must be changed at first login (NOT in the sudo group).
    if ! id operator &>/dev/null; then
        useradd --create-home --shell /bin/bash operator
    fi
    echo "operator:${DEFAULT_LOGIN_PASSWORD}" | chpasswd
    chage -d 0 operator
}

# --------------------------------------------------------------------------
# 3. Create the PostgreSQL database and role
# --------------------------------------------------------------------------
create_database() {
    log "Creating the PostgreSQL database and role..."
    systemctl enable --now postgresql

    # Generated once per run and written into the config file below.
    DB_PASSWORD="$(openssl rand -hex 16)"

    # Create or update the role (idempotent).
    sudo -u postgres psql -v ON_ERROR_STOP=1 <<SQL
DO \$do\$
BEGIN
    IF EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
        ALTER ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    ELSE
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
END
\$do\$;
SQL

    # Create the database if it does not exist yet.
    if ! sudo -u postgres psql -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" | grep -q 1; then
        sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"
    fi

    # PostgreSQL on Ubuntu listens on localhost only by default, which already
    # satisfies "the database must be reachable only from the VM". Make that
    # explicit and idempotent.
    local pg_conf
    pg_conf="$(sudo -u postgres psql -tAc 'SHOW config_file')"
    if [[ -f "${pg_conf}" ]]; then
        sed -i "s/^[#[:space:]]*listen_addresses.*/listen_addresses = 'localhost'/" "${pg_conf}"
        systemctl restart postgresql
    fi
}

# --------------------------------------------------------------------------
# 4. Generate the configuration file
# --------------------------------------------------------------------------
write_config() {
    log "Writing the configuration file ${CONFIG_FILE}..."
    install -d -m 750 "${CONFIG_DIR}"
    cat > "${CONFIG_FILE}" <<TOML
# mywebapp configuration — generated by deploy/install.sh
[server]
host = "${APP_HOST}"
port = ${APP_PORT}

[database]
host = "${DB_HOST}"
port = ${DB_PORT}
name = "${DB_NAME}"
user = "${DB_USER}"
password = "${DB_PASSWORD}"
TOML
    # Readable by root and by the application's group only (it holds a secret).
    chown -R root:"${APP_USER}" "${CONFIG_DIR}"
    chmod 750 "${CONFIG_DIR}"
    chmod 640 "${CONFIG_FILE}"
}

# --------------------------------------------------------------------------
# 5. Deploy the application code and its virtual environment
# --------------------------------------------------------------------------
deploy_app() {
    log "Deploying the application into ${APP_DIR}..."
    install -d -m 755 "${APP_DIR}"
    rm -rf "${APP_DIR}/app"
    cp -r "${REPO_DIR}/app" "${APP_DIR}/app"
    cp "${REPO_DIR}/requirements.txt" "${APP_DIR}/requirements.txt"

    python3 -m venv "${APP_DIR}/venv"
    "${APP_DIR}/venv/bin/pip" install --upgrade pip
    "${APP_DIR}/venv/bin/pip" install -r "${APP_DIR}/requirements.txt"

    # The application only needs to read its files.
    chown -R root:root "${APP_DIR}"
    chmod -R go-w "${APP_DIR}"
}

# --------------------------------------------------------------------------
# 6. Install the systemd socket and service (socket activation)
# --------------------------------------------------------------------------
install_systemd() {
    log "Installing the systemd socket and service units..."
    install -m 644 "${SCRIPT_DIR}/mywebapp.socket"  /etc/systemd/system/mywebapp.socket
    install -m 644 "${SCRIPT_DIR}/mywebapp.service" /etc/systemd/system/mywebapp.service
    systemctl daemon-reload
    # Only the socket is enabled; the service is started on demand by the socket.
    systemctl enable mywebapp.socket
}

# --------------------------------------------------------------------------
# 7. Run the migration and start the service
# --------------------------------------------------------------------------
start_service() {
    log "Running the database migration and starting the service..."
    # Explicit migration during install (the unit also runs it via ExecStartPre).
    ( cd "${APP_DIR}" && sudo -u "${APP_USER}" \
        env MYWEBAPP_CONFIG="${CONFIG_FILE}" \
        "${APP_DIR}/venv/bin/python" -m app.migrate )

    systemctl restart mywebapp.socket
    # Trigger the service now so it is ready immediately for testing.
    systemctl restart mywebapp.service
}

# --------------------------------------------------------------------------
# 8. Configure nginx as a reverse proxy
# --------------------------------------------------------------------------
configure_nginx() {
    log "Configuring nginx as a reverse proxy..."
    install -m 644 "${SCRIPT_DIR}/nginx-mywebapp.conf" \
        /etc/nginx/sites-available/mywebapp
    ln -sf /etc/nginx/sites-available/mywebapp /etc/nginx/sites-enabled/mywebapp
    # Remove the stock default site so our server block becomes the default.
    rm -f /etc/nginx/sites-enabled/default
    nginx -t
    systemctl enable nginx
    systemctl restart nginx
}

# --------------------------------------------------------------------------
# 9. Install the sudoers policy for the operator user
# --------------------------------------------------------------------------
install_sudoers() {
    log "Installing the sudoers policy for the operator user..."
    install -m 440 "${SCRIPT_DIR}/sudoers-operator" /etc/sudoers.d/operator
    visudo -cf /etc/sudoers.d/operator
}

# --------------------------------------------------------------------------
# 10. Write /home/student/gradebook (mandatory)
# --------------------------------------------------------------------------
write_gradebook() {
    log "Writing /home/student/gradebook..."
    echo "${GRADEBOOK_NUMBER}" > /home/student/gradebook
    chown student:student /home/student/gradebook
    chmod 644 /home/student/gradebook
}

# --------------------------------------------------------------------------
# 11. Lock the default OS user
# --------------------------------------------------------------------------
lock_default_user() {
    log "Locking the default OS user (${DEFAULT_OS_USER})..."
    if id "${DEFAULT_OS_USER}" &>/dev/null; then
        usermod -L "${DEFAULT_OS_USER}"
        usermod -s /usr/sbin/nologin "${DEFAULT_OS_USER}"
        chage -E 0 "${DEFAULT_OS_USER}" || true
    else
        echo "[install] default user '${DEFAULT_OS_USER}' not present — skipping"
    fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
main() {
    install_packages
    create_users
    create_database
    write_config
    deploy_app
    install_systemd
    start_service
    configure_nginx
    install_sudoers
    write_gradebook
    lock_default_user

    log "Installation complete."
    echo "    mywebapp is served by nginx on http://<vm-ip>/"
    echo "    Log in as: student (SSH key), teacher / operator (password ${DEFAULT_LOGIN_PASSWORD})."
}

main "$@"
