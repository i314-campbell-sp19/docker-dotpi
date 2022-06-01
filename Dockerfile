FROM alpine

RUN apk add --no-cache bind && \
    rndc-confgen -a -u root && \
    mkdir -p /var/cache/bind && \
    mkdir -p /var/run/named

COPY ./conf/named.conf /etc/bind/named.conf

EXPOSE 53/udp 53/tcp
CMD ["/usr/sbin/named","-g","-c","/etc/bind/named.conf"]
