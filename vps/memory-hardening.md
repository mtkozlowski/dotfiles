# VPS memory hardening

Target state for every Ubuntu VPS running interactive agent/dev workloads: a memory
overrun by one user kills one process in that user's slice, and never degrades the box
for anyone else.

## Guard layers

Four layers, innermost first. Each one catches what the one before it misses.

| Layer | Mechanism | Fires when | Kills |
|---|---|---|---|
| 1 | cgroup `MemoryHigh` | user tree exceeds soft cap | nothing — throttles and reclaims |
| 2 | cgroup `MemoryMax` | user tree exceeds its RAM cap | largest process in that slice |
| 3 | `systemd-oomd` PSI | slice stalls on memory above 60% for 20s, or swap above 90% used | highest-pressure descendant cgroup |
| 4 | `earlyoom` | whole box below free-memory floor | highest-RSS process, box-wide |

Layer 2 bounds damage. `MemoryMax` is the hard ceiling on one user's RAM, so a tree that
reaches it takes a kill inside its own slice and leaves the rest of the box alone. Swap
stays uncapped, which gives layer 1 reclaim somewhere to write and keeps a slice held at
`MemoryHigh` able to make progress.

Layer 3 gives per-pane granularity. tmux 3.6+ places each pane in its own
`tmux-spawn-<uuid>.scope`, so oomd's "kill the highest-pressure descendant" lands on a
single pane instead of a whole session.

Layer 4 is a backstop only. `earlyoom` requires available memory **and** free swap to both
be below their thresholds — the conditions are ANDed. A swap threshold of `-s 100,90`
makes the swap term always true and silently reduces the tool to a memory-only trigger.

## Thresholds

Per-user caps scale with box RAM and expected concurrent users:

- `MemoryMax` is 40 percent of total RAM per user
- `MemoryHigh` is 80 percent of `MemoryMax`
- `MemorySwapMax` is `infinity`

For an 8G box with two users: `MemoryMax=3G`, `MemoryHigh=2500M`,
`MemorySwapMax=infinity`. Two users can overcommit to 6G of 7.7G. `MemoryHigh` and
`MemoryMax` are what bound RAM, and per-user slices run with `MemorySwapMax=infinity` so
reclaim can make progress.

Size the swapfile to hold what the slices actually page out during normal work. Read
`memory.swap.current` per slice for that number. On an 8G box with two users at these
caps, uid 1000 alone has held 6981M.

`SwapUsedLimit` stays at the Ubuntu default of 90 percent. A slice sitting at
`MemoryHigh` pages out continuously, so ordinary work already occupies a large share of
the swapfile.

## Applying it

`vps/harden-memory.sh` is idempotent and computes caps from the box's own RAM. Run it as
root on any Ubuntu VPS:

```sh
sudo bash harden-memory.sh
```

It writes:

- `/etc/systemd/system/user-.slice.d/50-oom.conf` — per-user caps, pressure kill rule
- `/etc/sysctl.d/99-swap.conf` — `vm.swappiness=10`, `vm.vfs_cache_pressure=50`
- `/etc/systemd/oomd.conf.d/50-tune.conf` — swap and pressure limits
- `/etc/default/earlyoom` — retuned backstop thresholds

and installs `systemd-oomd` if absent.

### Package-install ordering

`systemd-oomd` must be restarted after installation. The unit starts during `apt` setup,
before dbus has loaded the policy granting the freshly-created `systemd-oom` user the
`org.freedesktop.oom1` bus name, and name acquisition is not retried. The service still
monitors correctly without the name — it reaches PID 1 as a client — but `oomctl` cannot
query it. `systemctl restart systemd-oomd` after install fixes it. The script does this.

## Verifying

```sh
# caps live on every user slice
for c in /sys/fs/cgroup/user.slice/user-*.slice; do
  echo "${c##*/} mem=$(cat $c/memory.max) swap=$(cat $c/memory.swap.max)"
done

# oomd running, name owned, slices monitored
systemctl is-active systemd-oomd
oomctl

# no duplicate or shadowing drop-ins
systemctl cat user-1000.slice | grep -E '^#|Memory'
systemd-delta --type=extended
```

Expect `memory.max` at the computed value and `memory.swap.max` reading `max` on every
`user-*.slice`, and both a "Swap
Monitored CGroups" and "Memory Pressure Monitored CGroups" section in `oomctl` listing
each active user slice. A user with no live session appears under swap monitoring but not
pressure monitoring; that is normal and resolves when they log in.

## Proving it fires

Config-correct is not proven-working. Run this on an idle box, in a throwaway tmux pane,
as a normal user:

```sh
# allocate faster than reclaim can keep up; expect death within ~30s
python3 -c 'a=[]
while True: a.append(bytearray(50*1024*1024))'
```

Watch from a second pane:

```sh
watch -n1 'free -m | head -3; cat /proc/pressure/memory'
journalctl -f -u systemd-oomd
dmesg -w | grep -i 'oom\|killed'
```

Success is the allocator dying while the second pane stays responsive throughout. If the
box becomes unresponsive instead, the caps are not applied to the slice the test ran in —
check `systemd-cgls` to confirm the test process is under `user-<uid>.slice`.

## Diagnosing a stalled box

Load average and free memory both mislead during thrash. The decisive readings:

```sh
cat /proc/pressure/memory          # full avg10 >50 means genuinely stalled, not busy
ps -eo stat,pid,user,comm | awk '/^D/'   # D-state count
for c in /sys/fs/cgroup/user.slice/user-*.slice; do
  echo "${c##*/} swap=$(( $(cat $c/memory.swap.current)/1048576 ))M"
done
```

Per-slice `memory.swap.current` attributes swap to a user directly and settles "whose
processes are the problem" without guessing.

Processes in D-state cannot receive SIGKILL — the signal stays pending until they leave
uninterruptible sleep, which a thrashing box may never allow. A `kill` that reports
success while swap usage does not drop means the signal never landed. At that point
userspace cannot recover the box and only a reboot will.

Reboot escalation, gentlest first:

```sh
sudo systemctl reboot                 # slow: 90s timeout per unit blocked on D-state
sudo systemctl reboot --force         # skips unit shutdown, still syncs and unmounts
echo 1 | sudo tee /proc/sys/kernel/sysrq
echo s | sudo tee /proc/sysrq-trigger # sync
echo b | sudo tee /proc/sysrq-trigger # immediate reboot, journal replay on boot
```

If no ssh connects at all: Hetzner Cloud console → server → Power → Reset. `hcloud server
reset <name>` does the same from a terminal.

## Open items

Carry these forward; none are done.

- [ ] **Docker is uncapped.** Containers run in `system.slice` with `memory.swap.max=max`,
      so no user-slice cap applies to them. A container leak reproduces the original
      failure with every guard above still green. Fix with per-container `mem_limit` in
      compose, or a dedicated slice via `cgroup-parent` in `/etc/docker/daemon.json`.
- [ ] **`earlyoom` retune on `eh`.** Still ships `-m 10,5 -s 100,90`, i.e. memory-only at
      5%. `harden-memory.sh` corrects this but has not been run on `eh`.
