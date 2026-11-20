# Proxmox QDevice Witness

Run a Corosync QNetd witness on a Home Assistant OS machine independent of your two Proxmox VE nodes. The witness provides a third quorum vote so a surviving Proxmox node can remain quorate when its peer goes offline. The app supports `amd64` Home Assistant OS hosts. [Proxmox external voting](https://pve.proxmox.com/pve-docs/chapter-pvecm.html#_corosync_external_vote_support)

## Install

In Home Assistant, go to **Settings → Apps → Install app → ⋮ → Repositories** and add `https://github.com/mattspera/ha-proxmox-qdevice-witness`. Install **Proxmox QDevice Witness**, enable **Start on boot**, and start the app. Supervisor builds the image on your Home Assistant OS host. [Home Assistant app repository guide](https://contributors.home-assistant.io/apps/guides/repository/)

Follow the [enrollment and recovery guide](proxmox_qdevice/DOCS.md) to connect the Proxmox cluster.

## Test locally

Build the `amd64` image and run the container smoke test with Docker and an OpenSSH client.

```sh
docker build --platform linux/amd64 -t qdevice-witness:0.1.0 proxmox_qdevice
bash tests/smoke.sh
```
