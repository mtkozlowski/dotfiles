#!/usr/bin/env bash
# Memory hardening for Ubuntu VPSs running interactive agent/dev workloads.
# Idempotent — safe to re-run. Caps are computed from the box's own RAM.
#
#   sudo bash harden-memory.sh          # apply
#   sudo bash harden-memory.sh --check  # report current state, change nothing
#
# See memory-hardening.md for the layer model and threshold rationale.

set -euo pipefail

CHECK_ONLY=0
[[ "${1:-}" == "--check" ]] && CHECK_ONLY=1
[[ $EUID -eq 0 ]] || { echo "run as root" >&2; exit 1; }

MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo)
MEM_MB=$(( MEM_KB / 1024 ))
MAX_MB=$(( MEM_MB * 40 / 100 ))    # per-user hard cap
HIGH_MB=$(( MAX_MB * 80 / 100 ))   # per-user throttle point
SWAP_MB=$(( MEM_MB * 10 / 100 ))   # per-user swap cap

report() {
  echo "== memory =="
  free -m | head -3
  echo "== per-user slice caps =="
  for c in /sys/fs/cgroup/user.slice/user-*.slice; do
    [[ -e "$c/memory.max" ]] || continue
    printf '%s  mem=%s  swap=%s\n' "${c##*/}" \
      "$(cat "$c/memory.max")" "$(cat "$c/memory.swap.max")"
  done
  echo "== guards =="
  printf 'systemd-oomd: %s\n' "$(systemctl is-active systemd-oomd 2>/dev/null || echo absent)"
  printf 'earlyoom:     %s\n' "$(systemctl is-active earlyoom 2>/dev/null || echo absent)"
  printf 'swappiness:   %s\n' "$(cat /proc/sys/vm/swappiness)"
  echo "== pressure =="
  cat /proc/pressure/memory
}

if [[ $CHECK_ONLY -eq 1 ]]; then
  report
  exit 0
fi

echo "RAM ${MEM_MB}M -> per user: MemoryMax=${MAX_MB}M MemoryHigh=${HIGH_MB}M MemorySwapMax=${SWAP_MB}M"

# --- layers 1+2: per-user cgroup caps ---------------------------------------
install -d /etc/systemd/system/user-.slice.d
cat > /etc/systemd/system/user-.slice.d/50-oom.conf <<EOF
[Slice]
MemoryHigh=${HIGH_MB}M
MemoryMax=${MAX_MB}M
MemorySwapMax=${SWAP_MB}M
MemoryPressureWatch=on
ManagedOOMMemoryPressure=kill
ManagedOOMMemoryPressureLimit=60%
EOF

# Ubuntu ships ManagedOOMSwap=kill on user.slice; assert it rather than assume.
install -d /etc/systemd/system/user.slice.d
cat > /etc/systemd/system/user.slice.d/50-oom.conf <<'EOF'
[Slice]
ManagedOOMSwap=kill
EOF

# --- layer 3: systemd-oomd ---------------------------------------------------
if ! systemctl list-unit-files systemd-oomd.service &>/dev/null; then
  DEBIAN_FRONTEND=noninteractive apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends systemd-oomd
fi

install -d /etc/systemd/oomd.conf.d
cat > /etc/systemd/oomd.conf.d/50-tune.conf <<'EOF'
[OOM]
# act before the swapfile is drained, not at the point of no return
SwapUsedLimit=70%
DefaultMemoryPressureLimit=60%
DefaultMemoryPressureDurationSec=20s
EOF

# --- layer 4: earlyoom backstop ----------------------------------------------
# Thresholds are ANDed: a swap floor near 100% would reduce this to memory-only.
if [[ -f /etc/default/earlyoom ]]; then
  cp -n /etc/default/earlyoom /etc/default/earlyoom.bak
  cat > /etc/default/earlyoom <<'EOF'
EARLYOOM_ARGS="-r 3600 -m 8,4 -s 15,8 --sort-by-rss \
--avoid ^(sshd|sshd-session|tmux|tmux:.*|systemd|systemd-.*|dbus-daemon|init)$ \
--prefer ^(claude|node|next-server|chrome|chromium|python.*|java)$"
EOF
fi

# --- keep anonymous pages resident -------------------------------------------
cat > /etc/sysctl.d/99-swap.conf <<'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl -q --system

# --- apply -------------------------------------------------------------------
systemctl daemon-reload
systemctl enable --now systemd-oomd
# Claim org.freedesktop.oom1: on a fresh install the unit starts before dbus
# loads its policy, and name acquisition is not retried.
systemctl restart systemd-oomd
systemctl is-active --quiet earlyoom && systemctl restart earlyoom || true

sleep 2
report
echo "== oomd view =="
oomctl 2>&1 | head -20
