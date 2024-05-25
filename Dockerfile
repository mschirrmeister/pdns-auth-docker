# Builder
FROM debian:12-slim AS builder

ENV NO_LUA_JIT="s390x arm64"

WORKDIR /source/

RUN apt-get update && apt-get -y dist-upgrade && apt-get clean \
    && apt-get install -y  --no-install-recommends \
       devscripts \
       dpkg-dev \
       equivs \
       git \
       liblua5.3-dev \
       python3-venv \
    && apt-get clean \
    && git clone --depth 1 -b auth-4.9.0 https://github.com/PowerDNS/pdns.git . \
    && git submodule init && git submodule update \
    && cp -p builder/helpers/set-configure-ac-version.sh /usr/local/bin \
    && mk-build-deps -i -t 'apt-get -y -o Debug::pkgProblemResolver=yes --no-install-recommends' /source/builder-support/debian/authoritative/debian-buster/control \
    && apt-get clean

ARG MAKEFLAGS=
ENV MAKEFLAGS ${MAKEFLAGS:--j2}

ARG DOCKER_FAKE_RELEASE=NO
ENV DOCKER_FAKE_RELEASE ${DOCKER_FAKE_RELEASE}

RUN if [ "${DOCKER_FAKE_RELEASE}" = "YES" ]; then \
      BUILDER_VERSION="$(IS_RELEASE=YES BUILDER_MODULES=authoritative ./builder-support/gen-version | sed 's/\([0-9]\+\.[0-9]\+\.[0-9]\+\(\(alpha|beta|rc\)\d\+\)\)?.*/\1/')" set-configure-ac-version.sh;\
    fi && \
    BUILDER_MODULES=authoritative autoreconf -vfi

# simplify repeated -C calls with SUBDIRS?
RUN mkdir /build && \
    LUAVER=$([ -z "${NO_LUA_JIT##*$(dpkg --print-architecture)*}" ] && echo 'lua5.3' || echo 'luajit') && \
    apt-get install -y lib${LUAVER}-*dev && \
    ./configure \
      --with-lua=${LUAVER} \
      --sysconfdir=/etc/powerdns \
      --enable-option-checking=fatal \
      --with-dynmodules='bind geoip gmysql godbc gpgsql gsqlite3 ldap lmdb lua2 pipe remote tinydns' \
      --enable-tools \
      --enable-ixfrdist \
      --with-unixodbc-lib=/usr/lib/$(dpkg-architecture -q DEB_BUILD_GNU_TYPE) \
    && make clean \
    && make $MAKEFLAGS -C ext && make $MAKEFLAGS -C modules && make $MAKEFLAGS -C pdns \
    && make -C pdns install DESTDIR=/build && make -C modules install DESTDIR=/build && make clean \
    && strip /build/usr/local/bin/* /build/usr/local/sbin/* /build/usr/local/lib/pdns/*.so \
    && cd /tmp && mkdir /build/tmp/ && mkdir debian \
    && echo 'Source: docker-deps-for-pdns' > debian/control \
    && dpkg-shlibdeps /build/usr/local/bin/* /build/usr/local/sbin/* /build/usr/local/lib/pdns/*.so \
    && sed 's/^shlibs:Depends=/Depends: /' debian/substvars >> debian/control \
    && equivs-build debian/control \
    && dpkg-deb -I equivs-dummy_1.0_all.deb && cp equivs-dummy_1.0_all.deb /build/tmp/

# Runtime
FROM debian:12-slim

COPY --from=builder /build /
COPY --from=builder /source/dockerdata/startup.py /usr/local/sbin/pdns_server-startup
COPY --from=builder /source/dockerdata/pdns.conf /etc/powerdns/

RUN chmod 1777 /tmp # FIXME: better not use /build/tmp for equivs at all
RUN apt-get update && apt-get -y dist-upgrade && apt-get clean \
    && apt-get install -y --no-install-recommends \
       python3 \
       python3-jinja2 \
       sqlite3 \
       tini \
       libcap2-bin \
       vim-tiny \
       supervisor \
       /tmp/equivs-dummy_1.0_all.deb \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm /var/log/apt/history.log \
    && rm /var/log/dpkg.log \
    && rm /var/log/apt/term.log \
    && mkdir -p /etc/powerdns/pdns.d /var/run/pdns /var/lib/powerdns /etc/powerdns/templates.d \
    && adduser --system --disabled-password --disabled-login --no-create-home --group pdns --uid 953 \
    && chown pdns:pdns /var/run/pdns /var/lib/powerdns /etc/powerdns/pdns.d /etc/powerdns/templates.d \
    && sqlite3 /var/lib/powerdns/pdns.sqlite3 < /usr/local/share/doc/pdns/schema.sqlite3.sql
    
USER pdns

EXPOSE 53/udp
EXPOSE 53/tcp
EXPOSE 8081/tcp

# ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/sbin/pdns_server-startup"]
CMD ["/usr/bin/tini", "--", "/usr/local/sbin/pdns_server-startup"]
