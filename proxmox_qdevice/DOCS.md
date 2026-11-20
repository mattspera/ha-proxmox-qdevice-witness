# Proxmox QDevice Witness

## Before enrollment

Use a Home Assistant OS host that can run independently of either Proxmox node. Reserve its LAN IP address, and allow both nodes to reach it on TCP `5403`. For a new cluster, join the second Proxmox node and verify both nodes are online before enrolling the witness.

Install the client on **each** Proxmox node as root.

```sh
apt update
apt install corosync-qdevice
```

## Enroll once from a Proxmox node

1. On the Proxmox node that will run setup, read the public key used by `pvecm` with `cat /root/.ssh/id_rsa.pub`. Paste the single public key line into **Proxmox enrollment public key** in the Home Assistant app configuration.
2. In the app's **Network** settings, publish the temporary SSH port by setting the host port for `22/tcp` to `2223`. Save and restart the app. Note the SSH host key fingerprint shown in its log.
3. On the initiating Proxmox node, add a host-specific entry near the top of `/root/.ssh/config`, before any general `Host *` defaults. Substitute the actual NUC IP for `192.0.2.10`. Use that same address in all subsequent commands.

   ```sshconfig
   Host 192.0.2.10
       Port 2223
       IdentityFile /root/.ssh/id_rsa
       IdentitiesOnly yes
   ```

4. Run `ssh root@192.0.2.10 true` and compare the fingerprint in the prompt with the app log before trusting the host key. Then run the enrollment and status commands.

   ```sh
   pvecm qdevice setup 192.0.2.10
   pvecm status
   ```

5. Confirm **Expected votes** and **Total votes** are both `3`, **Quorum** is `2`, and `Qdevice` appears in membership. Clear the public key setting and the host port for `22/tcp`, save, and restart the app. Remove the temporary SSH config entry from the initiating node. Once the QDevice reconnects, check `pvecm status` on both nodes and confirm the vote is back.

Proxmox enrolls over SSH and uses TCP `5403` for ongoing voting. Keep TCP `5403` reachable from both Proxmox nodes. [Proxmox QDevice setup and status flags](https://pve.proxmox.com/pve-docs/chapter-pvecm.html#_qdevice_net_setup)

## Test quorum and maintain the app

With both nodes online, reboot the NUC and verify that the QDevice rejoins on its own. During a maintenance window, stop one Proxmox node and verify the other is quorate with the QDevice. Bring the first node back before testing the other. With the two Proxmox nodes online and connected to each other, they retain quorum during a witness restart. Update the app while both Proxmox nodes are healthy, then confirm the QDevice reconnects. [Proxmox quorum behavior](https://pve.proxmox.com/pve-docs/chapter-pvecm.html#_corosync_external_vote_support)

After enrollment and after disabling SSH, create a Home Assistant backup that includes this app. The backup contains the witness certificate authority and key in the app's private data. Restore the app and its data together, and keep the same witness IP when replacing the NUC. Confirm the QDevice is active on both nodes after the restore. If the app reports damaged certificate state, restore a known-good app backup before restarting. [Home Assistant app storage](https://contributors.home-assistant.io/apps/reference/environment/)

## Remove or re-enroll the witness

With both Proxmox nodes online, run `pvecm qdevice remove` from one node, confirm `pvecm status` shows two expected votes, then stop or uninstall the app. If the witness identity was lost and you have a two-node cluster online, remove the existing QDevice before enrolling a freshly initialized app. Remove the QDevice before changing Proxmox cluster membership. [Proxmox QDevice removal](https://pve.proxmox.com/pve-docs/chapter-pvecm.html#_corosync_external_vote_support)
