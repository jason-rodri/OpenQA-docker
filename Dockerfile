FROM fedora:42

LABEL org.opencontainers.image.title="openQA for Rocky Linux"
LABEL org.opencontainers.image.description="Single-container openQA instance with TAP networking for Rocky Linux testing"
LABEL org.opencontainers.image.source="https://github.com/rocky-linux/openqa-rocky-docker"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL maintainer="Rocky Linux <infrastructure@rockylinux.org>"

# ── packages ──────────────────────────────────────────────────────────────────
RUN dnf install -y \
      git \
      openqa \
      openqa-httpd \
      openqa-worker \
      os-autoinst-openvswitch \
      openvswitch \
      qemu-kvm \
      qemu-img \
      ffmpeg-free \
      withlock \
      postgresql-server \
      perl-REST-Client \
      perl-JSON \
      python3-jsonschema \
      dbus-daemon \
      sudo \
      hostname \
      procps-ng \
      supervisor \
      bridge-utils \
      iproute \
      iptables \
      net-tools \
    --setopt=install_weak_deps=False \
    && dnf clean all

# ── PostgreSQL init ───────────────────────────────────────────────────────────
RUN mkdir -p /var/lib/pgsql/data /var/run/postgresql && \
    chown -R postgres:postgres /var/lib/pgsql /var/run/postgresql && \
    su - postgres -c '/usr/bin/initdb -D /var/lib/pgsql/data' && \
    sed -i 's/^host\s\+all\s\+all\s\+127.0.0.1\/32\s\+ident/host all all 127.0.0.1\/32 trust/' \
        /var/lib/pgsql/data/pg_hba.conf && \
    sed -i 's/^local\s\+all\s\+all\s\+peer/local all all trust/' \
        /var/lib/pgsql/data/pg_hba.conf

# ── httpd config ──────────────────────────────────────────────────────────────
RUN cp /etc/httpd/conf.d/openqa.conf.template /etc/httpd/conf.d/openqa.conf && \
    cp /etc/httpd/conf.d/openqa-ssl.conf.template /etc/httpd/conf.d/openqa-ssl.conf 2>/dev/null || true && \
    setsebool httpd_can_network_connect 1 2>/dev/null || true

# ── openQA config ─────────────────────────────────────────────────────────────
RUN cat > /etc/openqa/openqa.ini.d/10-rocky.ini <<'EOF'
[global]
branding=plain
download_domains = rockylinux.org

[auth]
method = Fake
EOF

# ── worker config ─────────────────────────────────────────────────────────────
RUN cat > /etc/openqa/workers.ini.d/10-rocky.ini <<'EOF'
[global]
host = http://localhost
backend = qemu

[1]
WORKER_CLASS = qemu_x86_64,tap
QEMUCPU = host
QEMURAM = 4096
QEMUCPUS = 4
EOF

# ── Rocky test suite ──────────────────────────────────────────────────────────
ARG DISTRI_BRANCH=main
ARG DISTRI_REPO=https://github.com/rocky-linux/os-autoinst-distri-rocky.git

RUN mkdir -p /var/lib/openqa/share/tests && \
    git clone --depth=1 -b ${DISTRI_BRANCH} ${DISTRI_REPO} \
        /var/lib/openqa/share/tests/rocky && \
    chown -R geekotest:geekotest /var/lib/openqa/share/tests/rocky

# ── directory ownership ───────────────────────────────────────────────────────
RUN mkdir -p /var/log/openqa && \
    chown -R geekotest:geekotest \
        /var/lib/openqa \
        /var/log/openqa \
        /etc/openqa/workers.ini.d

# ── OpenVSwitch database init ─────────────────────────────────────────────────
RUN mkdir -p /etc/openvswitch /run/openvswitch /var/log/openvswitch && \
    ovsdb-tool create /etc/openvswitch/conf.db \
        /usr/share/openvswitch/vswitch.ovsschema

# ── scripts ───────────────────────────────────────────────────────────────────
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
COPY worker-wrapper.sh /usr/local/bin/worker-wrapper.sh
COPY tap-setup.sh /usr/local/bin/tap-setup.sh
COPY ovs-setup.sh /usr/local/bin/ovs-setup.sh
RUN chmod +x /usr/local/bin/bootstrap.sh \
             /usr/local/bin/worker-wrapper.sh \
             /usr/local/bin/tap-setup.sh \
             /usr/local/bin/ovs-setup.sh

# ── supervisord config ────────────────────────────────────────────────────────
COPY supervisord.conf /etc/supervisord.conf

VOLUME ["/var/lib/openqa/share/factory/iso", \
        "/var/lib/openqa/share/factory/hdd", \
        "/var/lib/openqa/share/factory/other", \
        "/var/lib/openqa/testresults"]

EXPOSE 80 443

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
