# ─────────────────────────────────────────────────────────────
#  Overlay layer: adds desktop components and config files
#  on top of the base image
# ─────────────────────────────────────────────────────────────
ARG WEBCLAW_BASE_VERSION=latest
FROM land007/webclaw_base:${WEBCLAW_BASE_VERSION}

LABEL org.opencontainers.image.title="webclaw" \
      org.opencontainers.image.description="OpenClaw by WebClaw with editor, optional desktop, and isolated runtime" \
      org.opencontainers.image.url="https://github.com/land007/webcode" \
      org.opencontainers.image.source="https://github.com/land007/webcode" \
      org.opencontainers.image.vendor="land007" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.logo="https://raw.githubusercontent.com/land007/webclaw/main/images/icon-source.png" \
      org.opencontainers.image.version="${WEBCODE_VERSION:-dev}"

# Build-time flags (inherited from base, but can override)
ARG WEBCODE_VERSION=dev
ARG INSTALL_DESKTOP=true
ENV WEBCODE_VERSION=${WEBCODE_VERSION}

# ─── 6. GNOME Flashback desktop (VNC-compatible, no GL needed) ──────
# Note: intentionally NO --no-install-recommends here so gnome desktop
# components pull in all recommended packages for a complete desktop.
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        apt-get update && apt-get install -y \
            gnome-session-flashback gnome-terminal nautilus \
            metacity dbus-x11 gnome-panel gnome-settings-daemon \
            adwaita-icon-theme gnome-themes-extra \
            xfonts-base fonts-dejavu-core fonts-liberation2 fontconfig \
            fonts-hack \
            dconf-cli at-spi2-core \
            eog evince gnome-screenshot gedit xdg-user-dirs \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ─── 6b. Language packs for Chinese and English localization ─────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            language-pack-zh-hans language-pack-zh-hans-base \
            language-pack-gnome-zh-hans language-pack-gnome-zh-hans-base \
            language-pack-en language-pack-en-base \
            language-pack-gnome-en language-pack-gnome-en-base \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ─── 6b. GNOME / Terminal font defaults + panel layout fix ────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        mkdir -p /etc/dconf/profile /etc/dconf/db/local.d \
        && printf 'user-db:user\nsystem-db:local\n' > /etc/dconf/profile/user \
        && printf '[org/gnome/desktop/interface]\nmonospace-font-name='"'"'Hack 11'"'"'\n' \
           > /etc/dconf/db/local.d/00-terminal-font \
        && dconf update \
        && cp /usr/share/gnome-panel/layouts/default.layout \
           /usr/share/gnome-panel/layouts/gnome-flashback.layout \
        && cp /usr/share/gnome-panel/layouts/default.layout \
           /usr/share/gnome-panel/layouts/ubuntu.layout; \
    fi

# ─── 6c. hsetroot for dynamic background color switching ───────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        apt-get update && apt-get install -y --no-install-recommends hsetroot \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ─── 6d. Theme switch script (light/dark mode) ─────────────────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        if [ -f scripts/theme-switch.sh ]; then \
            cp scripts/theme-switch.sh /usr/local/bin/theme-switch \
            && chmod +x /usr/local/bin/theme-switch \
            && printf '\n# Theme switch aliases\nalias light-mode="/usr/local/bin/theme-switch light"\nalias dark-mode="/usr/local/bin/theme-switch dark"\n' >> /home/ubuntu/.bashrc; \
        fi; \
    fi

# ─── 6e. Language switch script (Chinese/English) ───────────────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        if [ -f scripts/lang-switch.sh ]; then \
            cp scripts/lang-switch.sh /usr/local/bin/lang-switch \
            && chmod +x /usr/local/bin/lang-switch \
            && printf '\n# Language switch aliases\nalias chinese="/usr/local/bin/lang-switch zh"\nalias english="/usr/local/bin/lang-switch en"\n' >> /home/ubuntu/.bashrc; \
        fi; \
    fi

# ─── 7. VNC + noVNC ─────────────────────────────────────────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        apt-get update && apt-get install -y \
            tigervnc-standalone-server tigervnc-common tigervnc-tools \
            x11-xserver-utils \
            python3 python3-numpy \
        && git clone --depth 1 --branch v1.5.0 https://github.com/novnc/noVNC.git /opt/noVNC \
        && git clone --depth 1 --branch v0.12.0 https://github.com/novnc/websockify.git /opt/noVNC/utils/websockify \
        && ln -s /opt/noVNC/vnc.html /opt/noVNC/index.html \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ─── 8. Chinese input (fcitx 4 + pinyin engines) ───────────────────
# Note: intentionally NO --no-install-recommends here so fcitx pulls
# in all frontends (gtk2/gtk3/xim), UI (classic), and IM modules.
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        apt-get update && apt-get install -y \
            fcitx fcitx-googlepinyin fcitx-pinyin fcitx-config-gtk \
            fonts-noto-cjk fonts-noto-cjk-extra \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ─── 8b. PulseAudio + Python WebSocket server deps ──────────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            pulseaudio pulseaudio-utils \
            python3-websockets \
            python3-pip \
            ffmpeg \
            libopus0 \
            gcc python3-dev \
        && apt-get clean && rm -rf /var/lib/apt/lists/* \
        && pip3 install --no-cache-dir --break-system-packages opuslib; \
    fi

# ─── 9. Docker CLI + daemon (auto-detect arch) ───────────────────────
# docker-ce and containerd.io are needed for DinD mode; cli is the primary use case.
# Packages are installed but daemon is NOT started by default — startup.sh handles DinD.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" \
       > /etc/apt/sources.list.d/docker.list \
    && apt-get update && apt-get install -y --no-install-recommends \
        docker-ce-cli docker-ce containerd.io docker-compose-plugin \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── 9b. Cloudflare Tunnel client (via official apt repo — avoids GitHub rate limits) ───
RUN curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg \
        | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null \
    && echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared noble main" \
        > /etc/apt/sources.list.d/cloudflared.list \
    && apt-get update && apt-get install -y --no-install-recommends cloudflared \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ─── 10. Browser: amd64=Google Chrome, arm64=Chromium ────────────────
# Use container-specific user-data-dir to avoid SingletonLock conflicts
# when multiple containers share the same chrome-data volume
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        if [ "$(dpkg --print-architecture)" = "amd64" ]; then \
            curl -LO https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
            && apt-get update && apt-get install -y ./google-chrome-stable_current_amd64.deb \
            && rm -f google-chrome-stable_current_amd64.deb \
            && printf '#!/bin/sh\nexport PULSE_SERVER="unix:/run/user/1000/pulse/native"\nexport PULSE_SINK="webcode_null"\nexport PULSE_SOURCE="webcode_mic"\nHOSTNAME=$$(hostname)\nUSER_DATA_DIR=/home/ubuntu/.config/google-chrome-$$HOSTNAME\nmkdir -p "$$USER_DATA_DIR"\nexec /usr/bin/google-chrome-stable --user-data-dir="$$USER_DATA_DIR" --password-store=basic "$@"\n' > /usr/local/bin/browser \
            && chmod +x /usr/local/bin/browser; \
        else \
            add-apt-repository -y ppa:xtradeb/apps \
            && apt-get update && apt-get install -y chromium \
            && printf '#!/bin/sh\nexport PULSE_SERVER="unix:/run/user/1000/pulse/native"\nexport PULSE_SINK="webcode_null"\nexport PULSE_SOURCE="webcode_mic"\nHOSTNAME=$$(hostname)\nUSER_DATA_DIR=/home/ubuntu/.config/chromium-$$HOSTNAME\nmkdir -p "$$USER_DATA_DIR"\nexec /usr/bin/chromium --user-data-dir="$$USER_DATA_DIR" --password-store=basic "$@"\n' > /usr/local/bin/browser \
            && chmod +x /usr/local/bin/browser; \
        fi \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ─── 11. User setup & docker group ──────────────────────────────────
RUN groupadd -f docker && usermod -aG docker ubuntu \
    && mkdir -p /home/ubuntu/projects /home/ubuntu/Desktop \
       /home/ubuntu/.local/share /home/ubuntu/.code-server \
    && echo 'alias docker="sudo /usr/bin/docker"' >> /home/ubuntu/.bashrc \
    && touch /home/ubuntu/.hushlogin \
    && chown -R ubuntu:ubuntu /home/ubuntu

# ─── 11b. nvm for ubuntu user ────────────────────────────────────────
RUN su -l ubuntu -c \
    'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash'

# ─── 11c. Node 22.22 + Claude Code via nvm ──────────────────────────
RUN su -l ubuntu -c \
    'source ~/.nvm/nvm.sh && \
     nvm install 22.22.0 && \
     nvm alias default 22.22.0 && \
     npm install -g @anthropic-ai/claude-code@latest'

# ─── 11d. v2rayN (GUI proxy client) ─────────────────────────────────
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        ARCH=$(dpkg --print-architecture) \
        && case "$ARCH" in \
            amd64) V2RAYN_ARCH=64 ;; \
            arm64) V2RAYN_ARCH=arm64 ;; \
            *) V2RAYN_ARCH="$ARCH" ;; \
        esac \
        && V2RAYN_VER=$(curl -fsSL https://api.github.com/repos/2dust/v2rayN/releases/latest | grep '"tag_name"' | cut -d'"' -f4) \
        && curl -fsSL "https://github.com/2dust/v2rayN/releases/download/${V2RAYN_VER}/v2rayN-linux-${V2RAYN_ARCH}.deb" -o /tmp/v2rayn.deb \
        && apt-get install -y /tmp/v2rayn.deb \
        && rm /tmp/v2rayn.deb \
        && apt-get clean && rm -rf /var/lib/apt/lists/*; \
    fi

# ─── 12. Config files (COPY last — most likely to change) ───────────
COPY configs/supervisord.conf /etc/supervisor/supervisord.conf
COPY configs/supervisord-lite.conf /etc/supervisor/conf.d/supervisord-lite.conf
COPY configs/supervisor-code-server.conf /etc/supervisor/conf.d/supervisor-code-server.conf
COPY configs/supervisor-openclaw.conf /etc/supervisor/conf.d/supervisor-openclaw.conf
COPY configs/supervisor-webtty.conf /etc/supervisor/conf.d/supervisor-webtty.conf
COPY configs/supervisor-cloudflared.conf /etc/supervisor/conf.d/supervisor-cloudflared.conf
COPY configs/supervisor-analytics.conf /etc/supervisor/conf.d/supervisor-analytics.conf
COPY configs/supervisor-dind.conf /etc/supervisor/conf.d/supervisor-dind.conf

# Dashboard server (needed for both desktop and lite modes)
COPY configs/supervisor-dashboard.conf /etc/supervisor/conf.d/supervisor-dashboard.conf

# Desktop-specific configs (audio, noVNC, desktop shortcuts)
COPY configs/supervisor-audio.conf /tmp/
COPY configs/audio-player.html /tmp/
COPY configs/audio-bar.js /tmp/
COPY configs/touch-handler.js /tmp/
COPY configs/key-remap.js /tmp/
COPY configs/xsession /tmp/
COPY scripts/audio-ws-server.py /tmp/
COPY scripts/audio-ws-wrapper.sh /tmp/
COPY scripts/start-dashboard.sh /opt/start-dashboard.sh
COPY scripts/start-webtty.sh /opt/start-webtty.sh
COPY configs/desktop-shortcuts/ /tmp/desktop-shortcuts/
COPY scripts/patch-novnc.sh /tmp/patch-novnc.sh
RUN if [ "$INSTALL_DESKTOP" = "true" ]; then \
        cp /tmp/supervisor-audio.conf /etc/supervisor/conf.d/ \
        && cp /tmp/audio-player.html /opt/noVNC/audio.html \
        && cp /tmp/audio-bar.js /opt/noVNC/audio-bar.js \
        && cp /tmp/touch-handler.js /opt/noVNC/touch-handler.js \
        && cp /tmp/key-remap.js /opt/noVNC/key-remap.js \
        && chmod +x /tmp/patch-novnc.sh \
        && /tmp/patch-novnc.sh \
        && cp /tmp/xsession /opt/xsession \
        && chmod +x /opt/xsession \
        && cp -r /tmp/desktop-shortcuts/ /opt/ \
        && cp /tmp/audio-ws-server.py /opt/ \
        && cp /tmp/audio-ws-wrapper.sh /opt/ \
        && chmod +x /opt/audio-ws-server.py /opt/audio-ws-wrapper.sh; \
    fi \
    && mkdir -p /opt/dashboard-override \
    && chown -R ubuntu:ubuntu /opt/dashboard-override \
    && chmod +x /opt/start-dashboard.sh /opt/start-webtty.sh \
    && rm -rf /tmp/supervisor-audio.conf /tmp/audio-player.html /tmp/audio-bar.js \
           /tmp/touch-handler.js /tmp/key-remap.js /tmp/xsession /tmp/desktop-shortcuts/ \
           /tmp/audio-ws-server.py /tmp/audio-ws-wrapper.sh \
           /tmp/patch-novnc.sh

COPY scripts/startup.sh /opt/startup.sh
COPY scripts/vnc-setpass.py /opt/vnc-setpass.py
COPY scripts/analytics.sh /scripts/analytics.sh
COPY scripts/dockerd-condition.sh /usr/local/bin/dockerd-condition.sh
COPY scripts/backup.sh /opt/backup.sh
COPY scripts/restore.sh /opt/restore.sh
COPY scripts/snapshot.sh /opt/snapshot.sh
COPY scripts/snapshot-restore.sh /opt/snapshot-restore.sh
COPY scripts/snapshot-base.sh /opt/snapshot-base.sh
RUN chmod +x /opt/startup.sh /scripts/analytics.sh /usr/local/bin/dockerd-condition.sh /opt/backup.sh /opt/restore.sh /opt/snapshot.sh /opt/snapshot-restore.sh /opt/snapshot-base.sh

# ─── 13. Skills for Claude Code (host-ops, etc.) ───────────────────────
COPY skills/ /opt/skills/
RUN mkdir -p /home/ubuntu/.claude/skills && \
    cp -r /opt/skills/* /home/ubuntu/.claude/skills/ && \
    chown -R ubuntu:ubuntu /home/ubuntu/.claude/skills

RUN echo "land007/webclaw" > /.image_name && \
    echo $(date "+%Y-%m-%d_%H:%M:%S") > /.image_time

# ─── Environment defaults ───────────────────────────────────────────
ENV MODE=desktop
ENV PASSWORD=
ENV VNC_RESOLUTION=1920x1080

ENTRYPOINT ["/opt/startup.sh"]

#docker build --build-arg INSTALL_DESKTOP=false -t land007/webclaw_lite:latest .
#docker build --build-arg INSTALL_DESKTOP=true -t land007/webclaw:latest .
