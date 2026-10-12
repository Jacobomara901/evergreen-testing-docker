FROM debian:bookworm AS base

ARG EG_REPO=https://github.com/evergreen-library-system/Evergreen.git
ARG EG_REF=rel_3_17
ARG OSRF_REPO=https://github.com/evergreen-library-system/OpenSRF.git
ARG OSRF_REF=main
ARG EG_STAFF_CLIENT=1

ENV DEBIAN_FRONTEND=noninteractive \
    PERL_MM_USE_DEFAULT=1 \
    NO_CPAN_TEST=1 \
    NODE_OPTIONS=--max-old-space-size=2048 \
    PATH=/openils/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git gnupg less lsb-release make openssl \
      procps tar unzip wget xz-utils \
 && rm -rf /var/lib/apt/lists/*

RUN useradd --create-home --shell /bin/bash opensrf

RUN git clone --depth 1 --branch "$OSRF_REF" "$OSRF_REPO" /usr/src/opensrf \
 && cd /usr/src/opensrf \
 && apt-get update \
 && make -f src/extras/Makefile.install debian-bookworm \
 && rm -rf /var/lib/apt/lists/*

RUN cd /usr/src/opensrf \
 && autoreconf -i \
 && ./configure --prefix=/openils --sysconfdir=/openils/conf \
 && make -j2 \
 && make install \
 && echo /openils/lib > /etc/ld.so.conf.d/opensrf.conf \
 && ldconfig \
 && rm -rf /usr/src/opensrf

COPY files/redis-accounts-setup /usr/local/bin/redis-accounts-setup
RUN chmod 755 /usr/local/bin/redis-accounts-setup && /usr/local/bin/redis-accounts-setup

RUN git clone --depth 1 --branch "$EG_REF" "$EG_REPO" /usr/src/evergreen \
 && cd /usr/src/evergreen \
 && apt-get update \
 && make -f Open-ILS/src/extras/Makefile.install debian-bookworm \
 && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    cd /usr/src/evergreen; \
    apt-get update; \
    make -f Open-ILS/src/extras/Makefile.install debian-bookworm-developer; \
    rm -f /usr/src/evergreen/node-*.tar.xz; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    cd /usr/src/evergreen/Open-ILS/web/opac/deps; \
    npm ci; \
    rm -rf /root/.npm

RUN set -eux; \
    [ "$EG_STAFF_CLIENT" = 1 ] || exit 0; \
    cd /usr/src/evergreen/Open-ILS/web/js/ui/default/staff; \
    npm ci; \
    npm run build-prod; \
    cd /usr/src/evergreen/Open-ILS/src/eg2; \
    npm ci; \
    npx ng build --configuration=production; \
    rm -rf /usr/src/evergreen/Open-ILS/web/js/ui/default/staff/node_modules; \
    rm -rf /usr/src/evergreen/Open-ILS/src/eg2/node_modules; \
    rm -rf /root/.npm

RUN cd /usr/src/evergreen \
 && autoreconf -i \
 && ./configure --prefix=/openils --sysconfdir=/openils/conf \
 && make \
 && make install \
 && ldconfig

RUN set -eux; \
    cd /usr/src/evergreen; \
    mkdir -p /usr/src/eg-runtime/Open-ILS/src /usr/src/eg-runtime/Open-ILS/tests/datasets; \
    cp -a Open-ILS/src/support-scripts /usr/src/eg-runtime/Open-ILS/src/; \
    cp -a Open-ILS/src/sql /usr/src/eg-runtime/Open-ILS/src/; \
    cp -a Open-ILS/src/extras /usr/src/eg-runtime/Open-ILS/src/; \
    cp -a Open-ILS/tests/datasets/sql /usr/src/eg-runtime/Open-ILS/tests/datasets/; \
    cp -a Open-ILS/examples /usr/src/eg-runtime/Open-ILS/; \
    rm -rf /usr/src/evergreen; \
    mv /usr/src/eg-runtime /usr/src/evergreen

FROM base AS loader

ARG EG_SAMPLE_DATA=concerto_enhanced

ENV EG_SAMPLE_DATA=${EG_SAMPLE_DATA}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      postgresql-16 \
      postgresql-contrib-16 \
      postgresql-plperl-16; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    sample=/usr/share/postgresql/16/postgresql.conf.sample; \
    perl -pi -e "s{^#?listen_addresses\s*=\s*\S+.*}{listen_addresses = '*'}" "$sample"; \
    grep -qF "listen_addresses = '*'" "$sample"; \
    printf '%s\n' 'jit = off' 'jit_above_cost = -1' >> "$sample"

COPY files/db-load /usr/local/bin/db-load
RUN chmod 755 /usr/local/bin/db-load && /usr/local/bin/db-load

FROM postgres:16-bookworm AS db

ENV DEBIAN_FRONTEND=noninteractive \
    PGDATA=/var/lib/postgresql/evergreen

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      cpanminus \
      gcc \
      libbusiness-isbn-perl \
      libjson-xs-perl \
      liblibrary-callnumber-lc-perl \
      libmarc-record-perl \
      libmarc-xml-perl \
      libmime-base32-perl \
      libperl-dev \
      librose-uri-perl \
      libuuid-tiny-perl \
      libxml-libxml-perl \
      libxml-libxslt-perl \
      make \
      postgresql-contrib-16 \
      postgresql-plperl-16 \
 && cpanm --notest --quiet String::KeyboardDistance Pass::OTP Text::Levenshtein::Damerau::XS \
 && apt-get purge -y --auto-remove cpanminus gcc libperl-dev make \
 && rm -rf /var/lib/apt/lists/* /root/.cpanm

COPY --from=loader --chown=postgres:postgres /var/lib/postgresql/evergreen /var/lib/postgresql/evergreen

FROM base AS app

RUN set -eux; \
    cd /usr/src/evergreen/Open-ILS/examples/apache_24; \
    cp eg_24.conf /etc/apache2/sites-available/eg.conf; \
    cp eg_vhost_24.conf /etc/apache2/eg_vhost.conf; \
    cp eg_startup /etc/apache2/eg_startup; \
    perl -pi -e 's{Require host 10\.0\.0\.0/8}{Require all granted}g' /etc/apache2/sites-available/eg.conf; \
    perl -pi -e 's{^\s*CustomLog\s+.*}{CustomLog /dev/stdout combined}g' /etc/apache2/sites-available/eg.conf; \
    perl -pi -e 's{^\s*ErrorLog\s+.*}{ErrorLog /dev/stderr}g' /etc/apache2/sites-available/eg.conf; \
    perl -pi -e 's{^(\s*SSLProxyEngine\s+on)\s+#.*}{$1}g' /etc/apache2/sites-available/eg.conf; \
    perl -pi -e 's{^KeepAliveTimeout.*}{KeepAliveTimeout 1}g' /etc/apache2/apache2.conf; \
    perl -pi -e 's{^MaxKeepAliveRequests.*}{MaxKeepAliveRequests 100}g' /etc/apache2/apache2.conf; \
    perl -pi -e 's{APACHE_RUN_USER=.*}{APACHE_RUN_USER=opensrf}g' /etc/apache2/envvars; \
    printf '%s\n' \
      '<IfModule mpm_prefork_module>' \
      '    StartServers            1' \
      '    MinSpareServers         1' \
      '    MaxSpareServers         2' \
      '    MaxRequestWorkers       8' \
      '    MaxConnectionsPerChild 500' \
      '</IfModule>' > /etc/apache2/mods-available/mpm_prefork.conf; \
    mkdir -p /etc/apache2/ssl; \
    openssl req -new -x509 -days 3650 -nodes \
      -out /etc/apache2/ssl/server.crt -keyout /etc/apache2/ssl/server.key \
      -subj '/C=GB/ST=Devon/L=Exeter/O=evergreen-testing-docker/CN=localhost'; \
    a2dismod -f mpm_event; \
    a2enmod mpm_prefork ssl proxy proxy_http proxy_wstunnel expires headers include rewrite cgi perl; \
    a2dissite 000-default; \
    a2ensite eg; \
    mkdir -p /var/lock/apache2; \
    chown opensrf /var/lock/apache2

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /tmp/websocketd.zip \
      "https://github.com/joewalnes/websocketd/releases/download/v0.4.1/websocketd-0.4.1-linux_${arch}.zip"; \
    unzip -j -o /tmp/websocketd.zip websocketd -d /usr/local/bin; \
    chmod 755 /usr/local/bin/websocketd; \
    rm -f /tmp/websocketd.zip

COPY files/opensrf-configure /usr/local/bin/opensrf-configure
RUN chmod 755 /usr/local/bin/opensrf-configure && /usr/local/bin/opensrf-configure

COPY files/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY files/aspen-export /usr/local/bin/aspen-export
COPY files/settings_ping.pl /usr/local/share/etd/settings_ping.pl
COPY files/sql/ /usr/local/share/etd/sql/

RUN set -eux; \
    chmod 755 /usr/local/bin/entrypoint.sh /usr/local/bin/aspen-export; \
    mkdir -p /exports/aspen/marc /exports/aspen/marc_delta /exports/aspen/supplemental; \
    chown -R opensrf:opensrf /exports /openils; \
    chmod -R a+rX /exports

ENV OSRF_HOSTNAME=evergreen

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
