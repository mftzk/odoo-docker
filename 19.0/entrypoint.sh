#!/bin/bash

set -e

if [ -v PASSWORD_FILE ]; then
    PASSWORD="$(< $PASSWORD_FILE)"
fi

# set the postgres database host, port, user and password according to the environment
# and pass them as arguments to the odoo process if not present in the config file
: ${HOST:=${DB_PORT_5432_TCP_ADDR:='db'}}
: ${PORT:=${DB_PORT_5432_TCP_PORT:=5432}}
: ${USER:=${DB_ENV_POSTGRES_USER:=${POSTGRES_USER:='odoo'}}}
: ${PASSWORD:=${DB_ENV_POSTGRES_PASSWORD:=${POSTGRES_PASSWORD:='odoo'}}}

DB_ARGS=()
function check_config() {
    param="$1"
    value="$2"
    if grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then       
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" |cut -d " " -f3|sed 's/["\n\r]//g')
    fi;
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}
check_config "db_host" "$HOST"
check_config "db_port" "$PORT"
check_config "db_user" "$USER"
check_config "db_password" "$PASSWORD"

# Function to check if database is initialized
check_db_initialized() {
    local db_name="$1"
    if [[ -z "$db_name" ]]; then
        return 1  # Not initialized if no DB name
    fi

    # Check if database exists and base module is installed
    python3 -c "
import psycopg2
import sys
try:
    conn = psycopg2.connect(
        host='${HOST}',
        port='${PORT}',
        user='${USER}',
        password='${PASSWORD}',
        dbname='${db_name}'
    )
    cursor = conn.cursor()
    # Check if base module is installed
    cursor.execute(\"SELECT state FROM ir_module_module WHERE name = 'base' LIMIT 1\")
    result = cursor.fetchone()
    cursor.close()
    conn.close()
    if result and result[0] == 'installed':
        sys.exit(0)  # Database is initialized
    else:
        sys.exit(1)  # Database exists but not fully initialized
except psycopg2.errors.InvalidCatalogName:
    sys.exit(1)  # Database doesn't exist
except Exception as e:
    sys.exit(1)  # Any other error, assume not initialized
"
    return $?
}

ODOO_CMD_ARGS=()
if [[ "${INIT,,}" == "true" ]]; then
    # Check if database needs initialization
    if [[ -n "${DB_NAME}" ]]; then
        if ! check_db_initialized "${DB_NAME}"; then
            echo "Database '${DB_NAME}' not initialized or doesn't exist. Running initialization..."
            ODOO_CMD_ARGS+=("--init" "base")
            ODOO_CMD_ARGS+=("-d" "${DB_NAME}")
        else
            echo "Database '${DB_NAME}' already initialized. Skipping initialization."
        fi
    else
        # If no specific DB name, always try to init (legacy behavior)
        echo "INIT=true: No specific database name provided, running initialization..."
        ODOO_CMD_ARGS+=("--init" "base")
    fi
else
    echo "INIT not set to true. Current value: '${INIT}'"
fi

case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            exec odoo "$@"
        else
            wait-for-psql.py ${DB_ARGS[@]} --timeout=30
            exec odoo "${ODOO_CMD_ARGS[@]}" "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        wait-for-psql.py ${DB_ARGS[@]} --timeout=30
        exec odoo "${ODOO_CMD_ARGS[@]}" "$@" "${DB_ARGS[@]}"
        ;;
    *)
        exec "$@"
esac

exit 1
