FROM ghcr.io/home-assistant/base-debian:trixie

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        corosync-qnetd openssh-server openssl \
    && rm -rf /var/lib/apt/lists/* /etc/corosync/qnetd \
    && rm -f /etc/ssh/ssh_host_* \
    && ln -s /data/qnetd /etc/corosync/qnetd

COPY rootfs /

RUN chmod 0755 /etc/cont-init.d/10-qnetd /etc/cont-init.d/20-enrollment-ssh \
    /etc/services.d/qnetd/run /usr/local/libexec/qdevice/ssh-run
