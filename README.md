# save-dapla-deploy

Roswell/Consfigurator deploy of the service at `save.dapla.net`.

## Repository Layout

```
save-dapla-deploy.ros   Thin Roswell entry point
save-dapla-deploy.asd   Umbrella ASDF system definition
qlfile         Qlot dependency pins
src/deploy.lisp  Consfigurator properties and DEFHOST
src/docs.lisp    40ants-doc sections
t/e2e.lisp       Post-deploy FiveAM smoke tests
docs.ros         Documentation generator
Makefile         build / test / doc / dist / clean
```

## Installation

```sh
ros install qlot
qlot install
./save-dapla-deploy.ros
```

## Runbook

```sh
machinectl shell save@ -- systemctl --user status
machinectl shell save@ -- journalctl --user -f
machinectl shell save@ -- podman auto-update
```

Redeploy by re-running `./save-dapla-deploy.ros`. Idempotent.

## Playbook

### ZFS replication (rsync.net)

```sh
zfs snapshot storage/containers/save@$(date +%Y%m%d)
zfs send -w storage/containers/save@$(date +%Y%m%d) | \
  ssh user@rsync.net zfs receive backup/save
```

Key files under `/etc/zfs-keys/` must be backed up separately.

## Decommission

```sh
machinectl shell save@ -- systemctl --user stop save
machinectl shell save@ -- systemctl --user disable save
zfs destroy -r storage/users/save
zfs destroy -r storage/containers/save
```

## License

BSD 3-Clause. See [LICENSE](LICENSE).
