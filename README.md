# Ubuntu Settings Test Host

Creates a disposable Ubuntu Desktop VM using the supplied unattended-install configuration. It expects libvirt's default network, where the host is `192.168.122.1`.

```sh
./spawn.sh /path/to/ubuntu-desktop.iso
```

The installed account is `test` with password `test`. After installation, open its display, clone and run the settings repository:

```sh
git clone https://github.com/premot/ubuntu-settings.git
cd ubuntu-settings
./setup.sh
sudo reboot
```

Create a clean snapshot before testing changes:

```sh
virsh snapshot-create-as ubuntu-settings-test before-setup
```

Restore it to repeat a test:

```sh
virsh snapshot-revert ubuntu-settings-test before-setup
```
