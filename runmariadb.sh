#!/usr/bin/bash
PATH=$PATH:/usr/sbin/
DATADIR="/var/lib/mysql"
MARIADB_PASSWORD=${MARIADB_PASSWORD:-"change_me"}
MARIADB_CONF_FILE="/etc/my.cnf.d/mariadb-server.cnf"
MARIADB_CERT_FILE=/certs/mariadb/tls.crt
MARIADB_KEY_FILE=/certs/mariadb/tls.key

mkdir -p $(dirname ${MARIADB_CERT_FILE})
if [ -f "$MARIADB_CERT_FILE" ] && [ ! -f "$MARIADB_KEY_FILE" ] ; then
    echo "Missing TLS private key file ${MARIADB_KEY_FILE}"
    exit 1
fi
if [ ! -f "$MARIADB_CERT_FILE" ] && [ -f "$MARIADB_KEY_FILE" ] ; then
    echo "Missing TLS Certificate file ${MARIADB_CERT_FILE}"
    exit 1
fi

ln -sf /proc/self/fd/1 /var/log/mariadb/mariadb.log

if [ ! -d "${DATADIR}/mysql" ]; then
    crudini --set "$MARIADB_CONF_FILE" mysqld max_connections 64
    crudini --set "$MARIADB_CONF_FILE" mysqld max_heap_table_size 1M
    crudini --set "$MARIADB_CONF_FILE" mysqld innodb_buffer_pool_size 5M
    crudini --set "$MARIADB_CONF_FILE" mysqld innodb_log_buffer_size 512K

    # Config MariaDB to enable TLS
    if [ -f "$MARIADB_CERT_FILE" ]
    then
      crudini --set "$MARIADB_CONF_FILE" mariadb-10.3 ssl on
      crudini --set "$MARIADB_CONF_FILE" mariadb-10.3 ssl_cert "${MARIADB_CERT_FILE}"
      crudini --set "$MARIADB_CONF_FILE" mariadb-10.3 ssl_key "${MARIADB_KEY_FILE}"
    fi

    mysql_install_db --datadir="$DATADIR"

    chown -R mysql "$DATADIR"

    cat > /tmp/configure-mysql.sql <<-EOSQL
DELETE FROM mysql.user ;
CREATE USER 'ironic'@'localhost' identified by '${MARIADB_PASSWORD}' ;
GRANT ALL on *.* TO 'ironic'@'localhost' WITH GRANT OPTION ;
DROP DATABASE IF EXISTS test ;
CREATE DATABASE IF NOT EXISTS  ironic ;
FLUSH PRIVILEGES ;
EOSQL

    # mysqld_safe closes stdout/stderr if no bash options are set ($- == '')
    # turn on tracing to prevent this
    exec bash -x /usr/bin/mysqld_safe --init-file /tmp/configure-mysql.sql
else
    exec bash -x /usr/bin/mysqld_safe
fi
