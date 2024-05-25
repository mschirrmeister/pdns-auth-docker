# PowerDNS Authoritative Server

This project provides a **Dockerfile** for [**PowerDNS Authoritative Server**](https://github.com/PowerDNS/pdns) project.

Images are available on Dockerhub for `arm64` and `amd64`.

## Examples

Default

    docker run -it -d \
      --name pdns-auth \
      -p 53:53/tcp \
      -p 53:53/udp \
      -p 8081:8081/tcp \
      -v ./pdns.conf:/etc/powerdns/pdns.conf:ro \
      -e PUID=953 \
      -e PGID=953 \
      mschirrmeister/pdns-auth-49:latest

