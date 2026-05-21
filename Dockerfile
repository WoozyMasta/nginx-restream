ARG ALPINE_VERSION=3.23

# nginx build
FROM docker.io/library/alpine:$ALPINE_VERSION AS nginx-build

ARG NGINX_RTMP_VERSION=master
ARG NGINX_VERSION=1.30.1

# hadolint ignore=DL3018
RUN apk add --no-cache \
    build-base \
    linux-headers \
    git \
    ca-certificates \
    openssl-dev \
    openssl-libs-static

WORKDIR /src/nginx-rtmp-module

RUN set -eux; \
    git clone --depth 1 --single-branch --branch "$NGINX_RTMP_VERSION" \
      https://github.com/WoozyMasta/nginx-rtmp-module.git .

WORKDIR /src/nginx

RUN set -eux; \
    git clone --depth 1 --single-branch --branch "release-$NGINX_VERSION" \
      https://github.com/nginx/nginx.git .

ENV CFLAGS='-Os -fstack-protector-strong -D_FORTIFY_SOURCE=2'
ENV LDFLAGS='-static -s -Wl,-z,relro,-z,now'

RUN set -eux; \
    ./auto/configure \
      --builddir=build \
      --prefix=/share \
      --conf-path=/config/restream.conf \
      --sbin-path=/bin \
      --pid-path=/tmp/nginx.pid \
      --lock-path=/tmp/nginx.lock \
      --error-log-path=/dev/stderr \
      --http-log-path=/dev/stdout \
      --add-module=/src/nginx-rtmp-module \
      --with-cc-opt="$CFLAGS" \
      --with-ld-opt="$LDFLAGS" \
      --without-pcre \
      --without-http-cache \
      --without-http_charset_module \
      --without-http_gzip_module \
      --without-http_ssi_module \
      --without-http_userid_module \
      --without-http_auth_basic_module \
      --without-http_mirror_module \
      --without-http_autoindex_module \
      --without-http_geo_module \
      --without-http_map_module \
      --without-http_split_clients_module \
      --without-http_referer_module \
      --without-http_rewrite_module \
      --without-http_proxy_module \
      --without-http_fastcgi_module \
      --without-http_uwsgi_module \
      --without-http_scgi_module \
      --without-http_grpc_module \
      --without-http_memcached_module \
      --without-http_limit_conn_module \
      --without-http_limit_req_module \
      --without-http_empty_gif_module \
      --without-http_browser_module \
      --without-http_upstream_hash_module \
      --without-http_upstream_ip_hash_module \
      --without-http_upstream_least_conn_module \
      --without-http_upstream_random_module \
      --without-http_upstream_keepalive_module \
      --without-http_upstream_zone_module \
      --without-select_module \
      --without-poll_module; \
    make -j"$(nproc)"

WORKDIR /src/nginx/build

RUN set -eux; \
    strip -s -R .comment --strip-unneeded nginx; \
    ! ldd nginx && :; \
    ./nginx -V

WORKDIR /out/config
COPY config ./

WORKDIR /out/share/html
RUN cp /src/nginx-rtmp-module/stat.xsl .

WORKDIR /out/bin
RUN mv /src/nginx/build/nginx nginx

WORKDIR /out/tmp

# ffmpeg build
FROM docker.io/library/alpine:$ALPINE_VERSION AS ffmpeg-build

ARG FFMPEG_VERSION=7.1

# hadolint ignore=DL3018
RUN apk add --no-cache \
    build-base \
    linux-headers \
    git \
    nasm \
    pkgconf \
    openssl-dev \
    openssl-libs-static \
    zlib-dev \
    zlib-static \
    x264-dev

WORKDIR /src/ffmpeg

RUN set -eux; \
    git clone --depth 1 --single-branch --branch "n$FFMPEG_VERSION" \
      https://git.ffmpeg.org/ffmpeg.git .

ENV CFLAGS='-Os -fstack-protector-strong -D_FORTIFY_SOURCE=2'
ENV LDFLAGS='-static -s -Wl,-z,relro,-z,now'

RUN set -eux; \
    ./configure \
      --prefix=/out \
      --bindir=/out/bin \
      --enable-static \
      --disable-shared \
      --disable-debug \
      --disable-doc \
      --disable-ffplay \
      --disable-ffprobe \
      --enable-gpl \
      --enable-version3 \
      --enable-openssl \
      --enable-libx264 \
      --disable-everything \
      --enable-network \
      --enable-decoder=h264,aac,mp3 \
      --enable-encoder=libx264,aac \
      --enable-demuxer=flv,live_flv \
      --enable-muxer=flv \
      --enable-protocol=rtmp,rtmps,tcp,tls,file,pipe \
      --enable-filter=scale,fps,format,aresample,aformat \
      --enable-bsf=h264_mp4toannexb,aac_adtstoasc \
      --extra-cflags="$CFLAGS" \
      --extra-ldflags="$LDFLAGS" \
      --extra-libs="-lpthread -lm"; \
    make -j"$(nproc)"; \
    make install

WORKDIR /out/bin
RUN set -eux; \
    strip -s -R .comment --strip-unneeded ffmpeg; \
    ! ldd ffmpeg && :; \
    ./ffmpeg -version

FROM scratch

COPY --from=nginx-build  --chown=1000:1000 /out /
COPY --from=ffmpeg-build --chown=1000:1000 /out/bin/ffmpeg /bin/ffmpeg

USER 1000:1000
STOPSIGNAL SIGQUIT

ENTRYPOINT ["/bin/nginx"]
CMD ["-g", "daemon off;"]
