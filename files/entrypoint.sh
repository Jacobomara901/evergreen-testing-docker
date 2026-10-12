#!/bin/bash
set -Eeuo pipefail

export PATH=/openils/bin:$PATH
export PGHOST=db
export PGPORT=5432
export PGUSER=evergreen
export PGPASSWORD=evergreen
export PGDATABASE=evergreen

EG_HTTP_PORT="${EG_HTTP_PORT:-8086}"
EG_SERVICES="${EG_SERVICES:-full}"

osrf_config=/openils/conf/opensrf.xml

staff_only_services=(
    opensrf.math
    opensrf.dbmath
    open-ils.acq
    open-ils.auth_proxy
    open-ils.booking
    open-ils.cat
    open-ils.collections
    open-ils.courses
    open-ils.curbside
    open-ils.ebook_api
    open-ils.geo
    open-ils.justintime
    open-ils.qstore
    open-ils.reporter
    open-ils.reporter-store
    open-ils.serial
    open-ils.sip2
    open-ils.url_verify
    open-ils.vandelay
)

check_service_selection() {
    if [ "$EG_SERVICES" = full ] || [ "$EG_SERVICES" = minimal ]; then
        return 0
    fi
    echo "etd: EG_SERVICES must be 'full' or 'minimal', not '$EG_SERVICES'" >&2
    exit 1
}

restore_opensrf_config() {
    echo "etd: restoring the packaged opensrf.xml"
    cp -f "$osrf_config.etd" "$osrf_config"
}

select_opensrf_services() {
    if [ "$EG_SERVICES" != minimal ]; then
        echo "etd: EG_SERVICES=full, starting every service"
        return 0
    fi
    echo "etd: EG_SERVICES=minimal, dropping ${#staff_only_services[@]} services"
    for service in "${staff_only_services[@]}"; do
        perl -ni -e "print unless m{<appname>\s*\Q$service\E\s*</appname>}" "$osrf_config"
    done
}

add_opensrf_domains_to_hosts() {
    if grep -q private.localhost /etc/hosts; then
        return 0
    fi
    echo "127.0.0.1 private.localhost public.localhost" >> /etc/hosts
}

wait_for_database_server() {
    echo "etd: waiting for postgres on $PGHOST:$PGPORT"
    until pg_isready -q -h "$PGHOST" -p "$PGPORT" -U "$PGUSER"; do
        sleep 2
    done
    echo "etd: postgres is accepting connections"
}

point_opensrf_at_database() {
    echo "etd: pointing opensrf.xml at the database"
    cd /usr/src/evergreen
    perl Open-ILS/src/support-scripts/eg_db_config \
        --update-config --service all --create-offline \
        --user evergreen --password evergreen \
        --hostname "$PGHOST" --port "$PGPORT" --database evergreen < /dev/null
}

start_redis() {
    echo "etd: starting redis"
    redis-server --daemonize yes --bind 127.0.0.1 --save '' --appendonly no
    until redis-cli -h 127.0.0.1 ping > /dev/null 2>&1; do
        sleep 1
    done
}

start_memcached() {
    echo "etd: starting memcached"
    memcached -d -u nobody -m 64 -l 127.0.0.1
}

start_opensrf_services() {
    echo "etd: starting opensrf services"
    su opensrf -c 'PATH=/openils/bin:$PATH osrf_control --localhost --start-all'
}

wait_for_settings_server() {
    echo "etd: waiting for the opensrf settings server"
    until su opensrf -c 'perl /usr/local/share/etd/settings_ping.pl' > /dev/null 2>&1; do
        sleep 2
    done
}

run_autogen() {
    echo "etd: running autogen"
    su opensrf -c 'PATH=/openils/bin:$PATH autogen.sh'
}

start_websocketd() {
    echo "etd: starting websocketd"
    su opensrf -c 'nohup /usr/local/bin/websocketd --port 7682 /openils/bin/osrf-websocket-stdio >> /openils/var/log/websocketd.log 2>&1 &'
}

prepare_apache() {
    mkdir -p /var/lock/apache2
    chown opensrf /var/lock/apache2
}

wait_for_apache() {
    until curl -fsS -o /dev/null http://127.0.0.1/eg/opac/home; do
        sleep 3
    done
}

print_ready_banner() {
    cat <<BANNER
etd: evergreen is ready
etd:   opac          http://localhost:$EG_HTTP_PORT/eg/opac/home
etd:   staff client  http://localhost:$EG_HTTP_PORT/eg2/en-US/staff/
etd:   gateway       http://localhost:$EG_HTTP_PORT/osrf-gateway-v1
etd:   staff login   admin / demo123
etd:   aspen export  /exports/aspen
BANNER
}

report_startup_failure() {
    echo "etd: startup failed running: $BASH_COMMAND" >&2
    kill 1
}

finish_startup() {
    trap report_startup_failure ERR
    wait_for_apache
    echo "etd: apache is answering, writing the aspen export"
    su opensrf -c /usr/local/bin/aspen-export
    touch /eg_ready
    print_ready_banner
}

rm -f /eg_ready
check_service_selection
add_opensrf_domains_to_hosts
wait_for_database_server
restore_opensrf_config
select_opensrf_services
point_opensrf_at_database
chown opensrf:opensrf "$osrf_config"
start_redis
start_memcached
start_opensrf_services
wait_for_settings_server
run_autogen
start_websocketd
prepare_apache
finish_startup &

exec apache2ctl -D FOREGROUND
