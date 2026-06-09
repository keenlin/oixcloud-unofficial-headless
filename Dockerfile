# syntax=docker/dockerfile:1

ARG BASE_IMAGE=lscr.io/linuxserver/baseimage-kasmvnc:ubuntunoble
ARG QUICKJS_C_BRIDGE_URL=https://github.com/abner/quickjs-c-bridge/archive/7204d9bf1afbe0550d51d7decdcce398b2c22e1a.tar.gz

FROM ubuntu:noble AS quickjs-c-bridge-builder

ARG QUICKJS_C_BRIDGE_URL

RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        cmake \
        curl \
        g++ \
        gcc \
        make; \
    curl -fsSL "$QUICKJS_C_BRIDGE_URL" -o /tmp/quickjs-c-bridge.tar.gz; \
    mkdir -p /tmp/quickjs-c-bridge; \
    tar -xzf /tmp/quickjs-c-bridge.tar.gz -C /tmp/quickjs-c-bridge --strip-components=1; \
    cmake -S /tmp/quickjs-c-bridge/linux -B /tmp/quickjs-c-bridge/build/linux -DCMAKE_BUILD_TYPE=Release; \
    cmake --build /tmp/quickjs-c-bridge/build/linux; \
    test -f /tmp/quickjs-c-bridge/build/linux/libquickjs_c_bridge_plugin.so

FROM ${BASE_IMAGE}

ARG TARGETARCH
ARG FLCLASH_AMD64_DEB_URL=https://dl.dler.io/flclash-linux-amd64.deb
ARG FLCLASH_ARM64_DEB_URL=https://dl.dler.io/flclash-linux-arm64.deb
ARG OCI_SOURCE=https://github.com/oixcloud-unofficial-headless

LABEL org.opencontainers.image.title="FlClash Headless" \
      org.opencontainers.image.description="Unofficial browser-accessible FlClash container" \
      org.opencontainers.image.source="${OCI_SOURCE}"

ENV TITLE="FlClash" \
    CUSTOM_PORT="3000" \
    START_DOCKER="false" \
    DISABLE_DRI="true" \
    NO_FULL="true" \
    LIBGL_ALWAYS_SOFTWARE="1" \
    GTK_USE_PORTAL="0" \
    LIBQUICKJSC_PATH="/usr/share/FlClash/lib/libquickjs_c_bridge_plugin.so"

RUN set -eux; \
    rm -f /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/nodesource.list; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        dbus-x11 \
        fontconfig \
        gnome-keyring \
        libayatana-appindicator3-1 \
        libegl1 \
        libgles2 \
        libkeybinder-3.0-0 \
        libsecret-1-0 \
        libsecret-tools \
        xdg-utils; \
    case "$TARGETARCH" in \
        amd64) flclash_deb_url="$FLCLASH_AMD64_DEB_URL" ;; \
        arm64) flclash_deb_url="$FLCLASH_ARM64_DEB_URL" ;; \
        *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1 ;; \
    esac; \
    curl -fsSL "$flclash_deb_url" -o /tmp/flclash.deb; \
    dpkg-deb -x /tmp/flclash.deb /; \
    ln -sf /usr/share/FlClash/FlClash /usr/bin/FlClash; \
    chmod +x /usr/share/FlClash/FlClash /usr/share/FlClash/FlClashCore /usr/bin/FlClash; \
    runtime_glibc="$(ldd --version | sed -n '1s/.* //p')"; \
    required_glibc="$(find /usr/share/FlClash -type f \( -name 'FlClash' -o -name 'FlClashCore' -o -name '*.so' \) -exec grep -Eaho 'GLIBC_[0-9]+\.[0-9]+' {} + | sed 's/^GLIBC_//' | sort -Vu | tail -n 1)"; \
    if [ -n "$required_glibc" ] && [ "$(printf '%s\n%s\n' "$runtime_glibc" "$required_glibc" | sort -V | tail -n 1)" != "$runtime_glibc" ]; then \
        echo "FlClash requires GLIBC_${required_glibc}, but base image provides glibc ${runtime_glibc}" >&2; \
        exit 1; \
    fi; \
    fc-cache -f; \
    rm -f /tmp/flclash.deb; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=quickjs-c-bridge-builder /tmp/quickjs-c-bridge/build/linux/libquickjs_c_bridge_plugin.so /usr/share/FlClash/lib/libquickjs_c_bridge_plugin.so
COPY root/ /

RUN chmod 755 /usr/share/FlClash/lib/libquickjs_c_bridge_plugin.so /defaults/autostart /etc/s6-overlay/s6-rc.d/init-flclash-autostart/run

EXPOSE 3000
