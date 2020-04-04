FROM golang:1.14.1 as gobuild
RUN set -x \
    && cd /root/ \
    && git clone https://github.com/shadowsocks/v2ray-plugin.git \
    && (cd v2ray-plugin/ \
    && go build) \
    && git clone https://github.com/xtaci/kcptun.git \
    && cd kcptun/ \
    && go mod download \
    && (cd server \
    && go build) \
    && (cd client \
    && go build)

####################################################################################

FROM alpine:3.11

LABEL maintainer="qiudog825@gmail.com"

ARG TZ='Asia/Chongqing'
ARG ARCH

ENV TZ ${TZ}
ENV SS_DOWNLOAD_URL https://github.com/shadowsocks/shadowsocks-libev.git 
ENV PLUGIN_OBFS_DOWNLOAD_URL https://github.com/shadowsocks/simple-obfs.git
ENV LINUX_HEADERS_DOWNLOAD_URL=http://dl-cdn.alpinelinux.org/alpine/v3.11/main/${ARCH}/linux-headers-4.19.36-r0.apk

COPY --from=gobuild /root/v2ray-plugin/v2ray-plugin /usr/bin/v2ray-plugin
COPY --from=gobuild /root/kcptun/server/server /usr/bin/kcpserver
COPY --from=gobuild /root/kcptun/client/client /usr/bin/kcpclient

RUN set -x \
    && apk upgrade \
    && apk add bash tzdata rng-tools runit \
    && apk add --virtual .build-deps \
        autoconf \
        automake \
        build-base \
        curl \
        c-ares-dev \
        libev-dev \
        libtool \
        libcap \
        libsodium-dev \
        mbedtls-dev \
        pcre-dev \
        tar \
        git \
    && curl -sSL ${LINUX_HEADERS_DOWNLOAD_URL} > /linux-headers.apk \
    && apk add --virtual .build-deps-kernel /linux-headers.apk \
    && git clone ${SS_DOWNLOAD_URL} \
    && (cd shadowsocks-libev \
    && git submodule update --init --recursive \
    && ./autogen.sh \
    && ./configure --prefix=/usr --disable-documentation \
    && make install) \
    && git clone ${PLUGIN_OBFS_DOWNLOAD_URL} \
    && (cd simple-obfs \
    && git submodule update --init --recursive \
    && ./autogen.sh \
    && ./configure --disable-documentation \
    && make install) \
    && for binPath in `ls /usr/bin/ss-* /usr/local/bin/obfs-* /usr/bin/kcp* /usr/bin/v2ray*`; do \
            setcap CAP_NET_BIND_SERVICE=+eip $binPath; \
       done \
    && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && apk del .build-deps .build-deps-kernel \
    && apk add --no-cache \
      $(scanelf --needed --nobanner /usr/bin/ss-* /usr/local/bin/obfs-* \
      | awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
      | sort -u) \
    && rm -rf /linux-headers.apk \
        shadowsocks-libev \
        simple-obfs \
        /etc/service \
        /var/cache/apk/*

SHELL ["/bin/bash"]

COPY runit /etc/service
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
