# Ubuntu Settings Test Host

Creates a disposable Ubuntu Desktop VM using the supplied unattended-install
configuration. The current implementation uses Ubuntu's **NoCloud-over-HTTP**
autoinstall method: the guest fetches `seed/meta-data` and `seed/user-data`
from the host at `192.168.122.1:3003`.

It expects libvirt's default NAT network, whose host address is normally
`192.168.122.1`.

```sh
./spawn.sh
```

The script installs its host requirements, downloads Ubuntu 24.04.4 Desktop on
its first run, resumes an interrupted download, and reuses the completed ISO
afterward.

The installed account is `test` with password `test`. After installation, open
its display, clone and run the settings repository:

```sh
git clone https://github.com/premot/ubuntu-settings.git
cd ubuntu-settings
./setup.sh
sudo reboot
```

Create a clean snapshot before testing changes:

```sh
sudo virsh snapshot-create-as ubuntu-settings-test before-setup
```

Restore it to repeat a test:

```sh
sudo virsh snapshot-revert ubuntu-settings-test before-setup
```

## Remove an old VM before spawning another

`spawn.sh` always uses the domain name `ubuntu-settings-test`. An old domain
with that name will prevent `virt-install` from creating a replacement. Use the
cleanup helper before starting over:

```sh
./cleanup-vm.sh
./spawn.sh
```

The helper shows the disks it found and forcibly only `ubuntu-settings-test`, removes its
libvirt definition, snapshots, managed-save/NVRAM state, and file-backed disks.
It does not touch other VMs, the Ubuntu installer ISO, the seed files, or the
libvirt `default` network.

If an old `spawn.sh` terminal is still running, stop it with `Ctrl-C` first so
its temporary seed HTTP server releases TCP port 3003.

### Manual clean-slate reset

The following is the manual equivalent. These commands permanently destroy the
VM and all data in its attached writable disks. Inspect the disk list **before**
deleting anything:

```sh
VM=ubuntu-settings-test
sudo virsh -c qemu:///system domblklist "$VM" --details

# Stop the guest (an error merely means it was already stopped).
sudo virsh -c qemu:///system destroy "$VM" || true
sudo virsh -c qemu:///system managedsave-remove "$VM" || true

# Remove the definition and snapshot/NVRAM metadata. On an older libvirt,
# remove unsupported flags and retry.
sudo virsh -c qemu:///system undefine "$VM" --snapshots-metadata --nvram

# Delete the disk path(s) shown as Type=file and Device=disk above.
# The usual path for this project is:
sudo rm -f /var/lib/libvirt/images/ubuntu-settings-test.qcow2
```

Confirm that no project domain remains:

```sh
sudo virsh -c qemu:///system list --all --name | grep -Fx ubuntu-settings-test \
  && echo 'still present' || echo 'VM definition is gone'
```

For a completely fresh project download as well, remove the cached installer
files. This is optional—neither file contains installed VM state, and retaining
the completed ISO makes the next spawn much faster:

```sh
rm -f ubuntu-24.04.4-desktop-amd64.iso \
      ubuntu-24.04.4-desktop-amd64.iso.part \
      seed/cidata.iso
```

Do not delete `/var/lib/libvirt` or reset the `default` network: both are shared
libvirt resources and may contain or support unrelated VMs. `spawn.sh` needs
the default network and will start it automatically.

## Troubleshooting an autoinstall failure

Do **not** shut down or reboot the VM when the installer shows its error. The
installer, cloud-init, and journal logs are initially in the live environment;
rebooting can discard the most useful evidence. Also leave the terminal that
ran `spawn.sh` open until the following capture is complete, because that
process owns the seed web server.

The generic Desktop installer error dialog is not the useful error. The useful
logs are usually `/var/log/installer/subiquity-server-debug.log`,
`/var/log/installer/curtin-install.log`, and `/var/log/cloud-init.log`.

### 1. Preserve the VM logs on the host

This procedure sends one compressed archive directly from the live VM to the
host. It does not require an SSH server or a shared filesystem. The Desktop ISO
includes `nc` (`netcat-openbsd`), which is used for the transfer.

On the **host**, in a second terminal, start this one-shot receiver *before*
running the command in the VM. It writes the archive outside the VM under
`artifacts/`:

```sh
mkdir -p artifacts
python3 -u - <<'PY'
from datetime import datetime
from pathlib import Path
import socket

path = Path("artifacts") / (
    "installer-logs-" + datetime.now().strftime("%Y%m%d-%H%M%S") + ".tar.gz"
)
with socket.create_server(("192.168.122.1", 3004)) as server:
    print(f"Waiting for one VM connection on 192.168.122.1:3004; writing {path}")
    connection, address = server.accept()
    print(f"Receiving from {address[0]}...")
    with connection, path.open("wb") as archive:
        while chunk := connection.recv(1024 * 1024):
            archive.write(chunk)
print(f"Saved {path}")
PY
```

In the errored VM, open a terminal from the live desktop. If the desktop is not
usable, switch to a text terminal with `Ctrl`+`Alt`+`F2`. Then collect the logs
and send them to the waiting host process:

```sh
sudo sh -c '
set -u
work=/tmp/autoinstall-debug
rm -rf "$work"
mkdir -p "$work"

for item in \
  /var/log/installer \
  /var/log/cloud-init.log \
  /var/log/cloud-init-output.log \
  /var/log/syslog \
  /var/log/kern.log
do
  [ -e "$item" ] && cp -a "$item" "$work/"
done

journalctl -b --no-pager >"$work/journalctl-current-boot.txt" 2>&1 || true
cat /proc/cmdline >"$work/kernel-command-line.txt"
ip address >"$work/ip-address.txt" 2>&1 || true
ip route >"$work/ip-route.txt" 2>&1 || true
wget -S -O /dev/null http://192.168.122.1:3003/user-data \
  >"$work/nocloud-user-data-fetch.txt" 2>&1 || true
'
sudo tar -C /tmp -czf - autoinstall-debug | nc -N 192.168.122.1 3004
```

Wait for the host receiver to print `Saved ...`. Verify and unpack the captured
archive on the host:

```sh
archive=$(find artifacts -maxdepth 1 -name 'installer-logs-*.tar.gz' -printf '%T@ %p\n' | sort -nr | head -1 | cut -d' ' -f2-)
tar -tzf "$archive"
dir=artifacts/unpacked-$(date +%Y%m%d-%H%M%S)
mkdir "$dir"
tar -xzf "$archive" -C "$dir"
```

The first files to inspect are:

```text
<unpacked>/autoinstall-debug/installer/subiquity-server-debug.log
<unpacked>/autoinstall-debug/installer/curtin-install.log
<unpacked>/autoinstall-debug/cloud-init.log
<unpacked>/autoinstall-debug/nocloud-user-data-fetch.txt
```

### 2. Preserve host-side libvirt evidence

The host also has the QEMU launch log and the active domain definition. Capture
them after the failure (and before deleting or redefining the domain):

```sh
stamp=$(date +%Y%m%d-%H%M%S)
dir="artifacts/host-$stamp"
mkdir -p "$dir"
sudo virsh dominfo ubuntu-settings-test >"$dir/domain-info.txt"
sudo virsh dumpxml ubuntu-settings-test >"$dir/domain.xml"
sudo virsh domblklist ubuntu-settings-test --details >"$dir/block-devices.txt"
sudo cp /var/log/libvirt/qemu/ubuntu-settings-test.log "$dir/qemu.log"
sudo chown -R "$USER":"$USER" "$dir"
```

The QEMU log confirms the kernel arguments actually supplied to the VM. It does
not normally contain the installer exception, which is why the in-VM archive in
the previous section is important.

### 3. Record whether the seed was fetched

For a repeat attempt, temporarily change the web-server launch in `spawn.sh`
from:

```sh
python3 -m http.server 3003 --directory seed --bind 0.0.0.0 &
```

to:

```sh
python3 -m http.server 3003 --directory seed --bind 0.0.0.0 \
  >seed-http.log 2>&1 &
```

After the failure, `seed-http.log` should show successful requests for both
`/meta-data` and `/user-data`.

- **No requests**: the guest did not reach the NoCloud HTTP datasource. Check
  `ip-route.txt` and `nocloud-user-data-fetch.txt` from the captured archive.
- **Both files return HTTP 200**: NoCloud was reached; use the Subiquity,
  Curtin, and cloud-init logs to find the actual installer exception.
- **A request returns 404**: the server is not being started from the expected
  `seed/` directory or the seed filenames have changed.

The configured kernel argument is intentionally quoted in `spawn.sh`:

```text
autoinstall ds=nocloud-net;s=http://192.168.122.1:3003/
```

The trailing slash is required, and the quoting prevents the shell from
interpreting the semicolon.

## More reliable local alternative: a NoCloud config-drive

NoCloud-over-HTTP is a supported autoinstall mechanism, but a local libvirt VM
can avoid its network dependency by attaching a NoCloud config-drive ISO. This
is often the more reliable option after an HTTP-based attempt fails.

Create it on the host:

```sh
sudo apt-get install -y cloud-image-utils
cloud-localds --filesystem iso seed/cidata.iso seed/user-data seed/meta-data
```

Then attach `seed/cidata.iso` to `virt-install` as a readonly CD-ROM and use
`--extra-args 'autoinstall'`. `cloud-localds` labels the media `cidata`, which
cloud-init discovers locally. This removes the temporary HTTP server, the
hard-coded gateway address, and early-boot guest networking from the
installation path.
