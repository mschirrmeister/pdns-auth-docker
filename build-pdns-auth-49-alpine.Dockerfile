# Builder
FROM alpine:3.20.0 AS builder

ENV NO_LUA_JIT="s390x arm64"

RUN apk add \
  boost-dev \
  curl \
  curl-dev \
  geoip-dev \
  krb5-dev \
  libmaxminddb-dev \
  libpq-dev \
  libsodium-dev \
  lmdb-dev \
  mariadb-connector-c-dev \
  mariadb-dev \
  openldap-dev \
  openssl-dev>3 \
  protobuf-dev \
  sqlite-dev \
  unixodbc-dev \
  yaml-cpp-dev \
  yaml-cpp-dev \
  zeromq-dev \
  protobuf-dev

#  luajit-dev-2.1_p20240314-r0 \
#  lua5.3-dev

WORKDIR /source/

RUN apk add \
  gcc \
  g++ \
  make \
  autoconf \
  automake \
  libtool \
  dpkg \
  dpkg-dev \
  git \
  bash \
  py3-virtualenv \
  debian-devscripts \
  bison \
  flex \
  ragel \
  unixodbc \
  && git clone --depth 1 -b auth-4.9.0 https://github.com/PowerDNS/pdns.git . \
  && git submodule init && git submodule update \
  && cp -p builder/helpers/set-configure-ac-version.sh /usr/local/bin

ARG MAKEFLAGS=
ENV MAKEFLAGS ${MAKEFLAGS:--j2}

ARG DOCKER_FAKE_RELEASE=NO
ENV DOCKER_FAKE_RELEASE ${DOCKER_FAKE_RELEASE}

RUN if [ "${DOCKER_FAKE_RELEASE}" = "YES" ]; then \
      BUILDER_VERSION="$(IS_RELEASE=YES BUILDER_MODULES=authoritative ./builder-support/gen-version | sed 's/\([0-9]\+\.[0-9]\+\.[0-9]\+\(\(alpha|beta|rc\)\d\+\)\)?.*/\1/')" set-configure-ac-version.sh;\
    fi && \
    BUILDER_MODULES=authoritative autoreconf -vfi

RUN mkdir /build && \
    LUAVER=$([ -z "${NO_LUA_JIT##*$(dpkg --print-architecture|awk -F'-' '{print $NF}')*}" ] && echo 'lua5.3' || echo 'luajit') && \
    apk add ${LUAVER}-dev && \
    ./configure \
      --with-lua=${LUAVER} \
      --sysconfdir=/etc/powerdns \
      --enable-option-checking=fatal \
      --with-dynmodules='bind geoip gmysql godbc gpgsql gsqlite3 ldap lmdb lua2 pipe remote' \
      --enable-tools \
      --enable-ixfrdist \
      --with-unixodbc-lib=/usr/lib \
    && make clean \
    && make $MAKEFLAGS -C ext && make $MAKEFLAGS -C modules && make $MAKEFLAGS -C pdns \
    && make -C pdns install DESTDIR=/build && make -C modules install DESTDIR=/build && make clean \
    && strip /build/usr/local/bin/* /build/usr/local/sbin/* /build/usr/local/lib/pdns/*.so 

# Runtime
FROM alpine:3.20.0

COPY --from=builder /build /
COPY --from=builder /source/dockerdata/startup.py /usr/local/sbin/pdns_server-startup
COPY --from=builder /source/dockerdata/pdns.conf /etc/powerdns/

# Ensure python3 and jinja2 is present (for startup script), and sqlite3 (for db schema), and tini (for signal management),
#   and vim (for pdnsutil edit-zone) , and supervisor (for special use cases requiring advanced process management)
RUN apk add --no-cache \
  python3 \
  py3-jinja2 \
  sqlite \
  tini \
  libcap-utils \
  libcap-getcap \
  libcap-setcap \
  mariadb-connector-c \
  libcurl \
  libsodium \
  lua5.3-libs \
  lmdb \
  boost-libs \
  supervisor \
  procps \
  && mkdir -p /etc/powerdns/pdns.d /var/run/pdns /var/lib/powerdns /etc/powerdns/templates.d \
  && addgroup -g 953 -S pdns \
  && adduser -S -D -H -g "" -G pdns -u 953 pdns \
  && sqlite3 /var/lib/powerdns/pdns.sqlite3 < /usr/local/share/doc/pdns/schema.sqlite3.sql \
  && chown pdns:pdns /var/run/pdns /var/lib/powerdns /etc/powerdns/pdns.d /etc/powerdns/templates.d /var/lib/powerdns/pdns.sqlite3 \
  && sed -i "1s|.*|#!/usr/bin/python3 -u|" /usr/local/sbin/pdns_server-startup

USER pdns

EXPOSE 53/udp
EXPOSE 53/tcp
EXPOSE 8081/tcp

#ENTRYPOINT ["/sbin/tini", "--", "/usr/local/sbin/pdns_server-startup"]
CMD ["/sbin/tini", "--", "/usr/local/sbin/pdns_server-startup"]
