# openvpn-systemd

Runs an OpenVPN client as a managed systemd unit: credentials held as an
encrypted systemd credential, and addresses that rotate behind a CDN kept pinned
to the tunnel device. Paired with the `vpn` shell function in `zsh/vpn.zsh`.

## Why each piece exists

**A systemd unit, not a shell job.** A tunnel started in a terminal dies with
the session that started it, has no scrollback after a crash, and does not
return after reboot. As a unit it restarts on failure, starts at boot, and logs
to journald — which is what gives `vpn logs --since` any history to read.

**A periodic route pinner.** The gated host resolves to anycast CDN addresses
that are not inside any subnet the VPN server pushes, so each address needs an
explicit `/32` route onto the tunnel device. Two properties make a one-shot pin
insufficient:

- The CDN's answer depends on where the query comes from, so addresses must be
  resolved through the tunnel's own resolver. A public resolver returns
  addresses that get pinned to a path the allowlist rejects with 403.
- OpenVPN's `--route-up` hook fires once per connect. A session that stays up
  for days never re-resolves, and the pins silently go stale when the answer
  rotates.

The timer re-resolves every 60s and drops pins the host no longer answers with.

**Credentials as an encrypted systemd credential.** OpenVPN reading credentials
from stdin cannot be run by a service manager, which is the usual reason such a
tunnel ends up living in a terminal. `vpn-creds-provision.sh` pipes the fields
straight from 1Password into `systemd-creds encrypt`, so plaintext never touches
disk and never appears in argv. The unit decrypts into `/run/credentials/…`
(tmpfs, `0400 root`, removed on stop).

Without a TPM the blob is bound to the systemd host key
(`/var/lib/systemd/credential.secret`, `0600 root`), so it is useless if copied
off the machine. It does **not** defend against root on this machine — root can
decrypt it, read the runtime credential, or read the daemon's memory.

## Configuration lives outside this repo

Every internal hostname, address, unit name and username sits in
`~/.config/vpn/site.conf` (mode `0600`), not in this repository, which is
public. The tracked files here are templates: `*.in` files carry `@TOKEN@`
placeholders that `install.sh` renders from `site.conf`.

Placing the real values outside the repo rather than in `.gitignore` means there
is no ignore rule to forget when adding a file.

Start from `site.conf.example`.

## Use

```sh
cp site.conf.example ~/.config/vpn/site.conf && chmod 0600 ~/.config/vpn/site.conf
$EDITOR ~/.config/vpn/site.conf
./vpn-creds-provision.sh     # as your user; op needs your token
./install.sh                 # renders templates, installs units, enables them
vpn status
```

`install.sh` is idempotent — re-run it after editing a template or `site.conf`.

It stops any hand-started `openvpn` using the same config first, since two
instances would fight over the tunnel device. On a shared host that drops the
tunnel for **every** user for a few seconds.

## Files

| file | role |
| --- | --- |
| `site.conf.example` | template for `~/.config/vpn/site.conf` |
| `vpn-creds-provision.sh` | 1Password → `systemd-creds encrypt` |
| `install.sh` | render templates, install, enable |
| `route-pin.sh.in` | re-resolve and pin the gated host's addresses |
| `routes.service.in` / `routes.timer.in` | run the pinner every 60s |
| `client-override.conf.in` | `Restart=`, `LimitNPROC=`, `LoadCredentialEncrypted=` |
| `nopasswd.sudoers.in` | password-free `systemctl` for these units only |

The sudoers policy enumerates each verb and unit; a wildcard would hand out
control of every service on the host. Credential provisioning is deliberately
excluded, so it still costs a password prompt.
