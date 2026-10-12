#!/bin/bash
set -euo pipefail

export PATH=/openils/bin:$PATH
export PGHOST=db
export PGPORT=5432
export PGUSER=evergreen
export PGPASSWORD=evergreen
export PGDATABASE=evergreen

EG_SAMPLE_DATA="${EG_SAMPLE_DATA:-concerto_enhanced}"
EG_HTTP_PORT="${EG_HTTP_PORT:-8086}"

sample_data_option=""
case "$EG_SAMPLE_DATA" in
    concerto_enhanced) sample_data_option=--load-concerto-enhanced ;;
    concerto) sample_data_option=--load-all-sample ;;
    none) sample_data_option="" ;;
    *) echo "etd: EG_SAMPLE_DATA must be concerto_enhanced, concerto or none" >&2; exit 1 ;;
esac

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

evergreen_database_exists() {
    local found
    found="$(psql -X -A -t -d postgres -c "SELECT 1 FROM pg_database WHERE datname = 'evergreen'")"
    [ "$found" = "1" ]
}

create_evergreen_database() {
    echo "etd: creating the evergreen database and loading $EG_SAMPLE_DATA, this takes several minutes"
    cd /usr/src/evergreen
    perl Open-ILS/src/support-scripts/eg_db_config \
        --update-config --service all \
        --create-database --create-schema --create-offline \
        --user evergreen --password evergreen \
        --hostname "$PGHOST" --port "$PGPORT" --database evergreen \
        --admin-user admin --admin-pass demo123 \
        $sample_data_option < /dev/null
    echo "etd: resetting the admin password"
    perl Open-ILS/src/support-scripts/eg_db_config \
        --user evergreen --password evergreen \
        --hostname "$PGHOST" --port "$PGPORT" --database evergreen \
        --admin-user admin --admin-pass demo123 < /dev/null
    echo "etd: database ready"
}

point_opensrf_at_database() {
    echo "etd: pointing opensrf.xml at the existing database"
    cd /usr/src/evergreen
    perl Open-ILS/src/support-scripts/eg_db_config \
        --update-config --service all \
        --user evergreen --password evergreen \
        --hostname "$PGHOST" --port "$PGPORT" --database evergreen < /dev/null
}

configure_database() {
    if evergreen_database_exists; then
        point_opensrf_at_database
        return 0
    fi
    create_evergreen_database
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

finish_startup() {
    wait_for_apache
    echo "etd: apache is answering, writing the aspen export"
    su opensrf -c /usr/local/bin/aspen-export
    touch /eg_ready
    print_ready_banner
}

rm -f /eg_ready
add_opensrf_domains_to_hosts
wait_for_database_server
configure_database
chown opensrf:opensrf /openils/conf/opensrf.xml
start_redis
start_memcached
start_opensrf_services
wait_for_settings_server
run_autogen
start_websocketd
prepare_apache
finish_startup &

exec apache2ctl -D FOREGROUND
