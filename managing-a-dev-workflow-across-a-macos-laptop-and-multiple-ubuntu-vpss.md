# Managing a Dev Workflow Across a macOS Laptop and Multiple Ubuntu VPSs (June 2026)

## TL;DR
- **Stop syncing code repos with file-sync tools; use git as the sync layer for repos and reserve Syncthing/Mutagen for non-repo working dirs (notes, configs, data).** Migrate dotfiles from Stow to **chezmoi** for true cross-OS templating and secrets, adopt **per-purpose ed25519 keys** (hardware-backed via Secure Enclave/Secretive or 1Password) with a clean `~/.ssh/config`, and lay **Tailscale** under everything as the connectivity fabric.
- **Pasting macOS screenshots into Claude Code over SSH is not yet solved natively** — Ghostty 1.3.x only *parses* (does not implement) the Kitty image-clipboard protocol, and Anthropic closed the Claude Code request as "not planned." Use a bridge tool: **cc-clip** (most seamless, transparent Ctrl+V) or **clipssh** (simplest), both relying on `pngpaste`; a Syncthing-synced screenshot folder or Taildrop is a solid lower-tech fallback.
- **Biggest single quality-of-life wins:** tmux (session persistence) + mosh (flaky links), atuin (synced shell history), and Tailscale (zero-config mesh, MagicDNS, Taildrop). Adopt these first; they are low-risk and compounding.

## Key Findings

### 1. Syncing key directories (including ones that are git repos)
- **Never bidirectionally sync a `.git` directory.** The git index records inode numbers, device IDs and mtimes specific to each filesystem, is rewritten on every `git status`, and `.git` can contain hooks that are a remote-code-execution vector. This is true for *any* sync tool (Syncthing, Mutagen, Unison, Dropbox).
- **The canonical pattern:** keep the authoritative `.git` on exactly **one** machine ("master"), sync only the working tree to the others, and exclude VCS dirs. Mutagen documents this explicitly and ships an `ignore: vcs: true` / `--ignore-vcs` flag. Crucially, **do NOT** keep a `.git` on both ends while excluding it from sync — `git commit` on one side leaves the other on the old commit and you cannot reconcile without a push/pull cycle.
- **Tooling fit:**
  - **git itself** = the correct sync layer for code. Commit on a WIP branch, push/pull (even peer-to-peer over SSH/Tailscale without a central remote). This is what virtually every experienced developer recommends for repos.
  - **Syncthing** = best for continuous, long-lived background sync of non-repo data (notes, configs, datasets, screenshot folders). Peer-to-peer, encrypted, runs as a daemon. Weakness: it chokes on directories full of git repos and its `.stignore` is per-folder-root only (use `#include` to sync the ignore file itself, since `.stignore` is never synced on its own).
  - **Mutagen** = best for *active remote-development* sync (laptop edits → VPS builds), sub-second latency via FSEvents/inotify, zero remote setup (auto-installs an agent over SSH). Caveats: real-world reports of high CPU and occasional conflict mishandling during heavy git operations.
  - **Unison** = mature bidirectional batch sync, but historically requires matching versions on both ends and is batch-oriented (its `repeat=watch` mode bolts on an external monitor).
  - **rsync** = one-shot / scripted pushes; not continuous.
- **Recommendation:** Code → git (clone fresh on each VPS, push/pull). Non-repo working dirs → Syncthing (continuous) or Mutagen (when actively editing locally + building remotely, with `ignore: vcs: true`).

### 2. Dotfiles / settings across macOS + multiple Ubuntu versions
- The current setup (git repo in `$HOME` + GNU Stow symlinking into `~/.config`) works but has real limits: **Stow only creates symlinks, has no templating, no secrets handling, and no OS-conditional logic** — exactly what you need when one machine is macOS and others are different Ubuntu releases. Migrating away from Stow is also manual (you must move every symlinked file back by hand).
- **chezmoi is the clear upgrade** and is purpose-built for "managing your dotfiles across multiple diverse machines, securely":
  - **Go text/template** templating keyed on `.chezmoi.os` (`darwin`/`linux`), `.chezmoi.hostname`, `.chezmoi.arch` — so one source file produces different output per machine (e.g. `HOMEBREW_PREFIX=/opt/homebrew` on macOS vs `/home/linuxbrew/.linuxbrew` on Linux).
  - **Secrets** via 1Password, Bitwarden, pass, Vault, KeePassXC, macOS Keychain, etc., *or* file encryption with **age**/GPG (`chezmoi add --encrypt`), so the repo can be checked out anywhere without revealing secrets.
  - Files are **copied, not symlinked**, so targets are normal files and you can stop using chezmoi anytime.
  - **`run_once_` / `run_onchange_` scripts** can bootstrap packages per-OS (e.g. `brew bundle` on darwin vs `apt-get install` on linux).
- Alternatives: **yadm** (bare-git wrapper, simplest if you love raw git, but its templating relies on third-party jinja tools like envtpl/j2cli that are weakly maintained), **bare git repo** (no deps, no templating/secrets), **Nix/home-manager** (most powerful and reproducible, but a steep learning curve and heavy for a few VPSs), **dotbot** (symlink bootstrapper, similar limits to Stow).
- **Recommendation: migrate Stow → chezmoi.** Migration is incremental: `chezmoi init`, `chezmoi add ~/.config/...` to import existing files, convert machine-varying files to templates with `chezmoi chattr +template`, and bootstrap new machines with one command (`chezmoi init --apply <github-user>`). Keep Stow until chezmoi covers everything, then remove the Stow symlinks.

### 3. SSH key strategy for multiple VPSs
- **Key type: ed25519, always.** It is the 2026 standard — fixed 256-bit (≈3072-bit RSA security), fast, side-channel-resistant, deterministic. Use RSA-4096 only as a legacy fallback. Avoid ECDSA/DSA.
- **One key for everything vs key-per-host — the pragmatic answer:** separate keys *by context/purpose and by client device*, not one-per-server. A widely held expert view (e.g. on Lobsters) is to use **one key per client device** (laptop key, desktop key) plus separate keys for distinct trust domains (e.g. a dedicated GitHub key you may need to rotate for compliance), and to be able to *explain the threat model* before going more granular. Per-VPS keys add management overhead (P×S) without much benefit for a single user; per-device keys mean losing a laptop only requires removing one public key everywhere.
- **Reuse vs separation:** Do not reuse a single key across wildly different trust domains. A separate GitHub key is sensible. The same laptop authentication key across your own VPSs is fine.
- **Hardware-backed keys (strongly recommended on the Mac):**
  - **Secure Enclave** (native since macOS Sequoia/Tahoe, or via the nicer **Secretive** app) keeps a non-extractable private key gated by Touch ID. Note Apple's native CryptoTokenKit prompt is ugly ("ctccardtoken needs to authenticate"); Secretive gives a cleaner UI.
  - **FIDO2 / `ed25519-sk`** (YubiKey) — private key never leaves the token, requires physical touch; needs OpenSSH 8.2+ (8.3+ for resident keys / `verify-required`) and (on macOS) Homebrew OpenSSH because Apple's bundled build disabled FIDO2.
  - **1Password SSH agent** — stores keys in the encrypted vault, presents them via an agent socket (`~/.1password/agent.sock`), works across machines; software-backed (decrypted in memory when used) but extremely convenient and can also manage `~/.ssh/config`.
  - Because hardware keys can't be backed up, **enroll a second key (backup YubiKey or another device) into every server's `authorized_keys`.**
- **`~/.ssh/config` hygiene:** Set `Host *` defaults `AddKeysToAgent yes`, `IdentitiesOnly yes` (critical when an agent holds many keys, or auth fails with "too many authentication failures"), `UseKeychain yes` (macOS), `ServerAliveInterval 60` / `ServerAliveCountMax 3`, and use **`ProxyJump`** (the modern replacement for ProxyCommand chains, since OpenSSH 7.3) for bastions. Use `Include config.d/*` to split config. Use **ControlMaster auto / ControlPersist** to multiplex connections and avoid re-auth per tab.
- **Agent forwarding vs ProxyJump:** Prefer **ProxyJump** — it keeps your private key off intermediate hosts. Use agent forwarding *only* to hosts you fully trust, since a compromised host can use the forwarded agent.
- **Certificates:** For one user with a handful of VPSs, full SSH CA infrastructure is overkill, but it is "worth the afternoon" if you want expiry-based rotation and to stop managing `authorized_keys` (turns P×S management into P+S).

### 4. Screenshots / clipboard into Claude Code over SSH (the hard one)
- **Why it's hard:** Claude Code reads images by shelling out to a clipboard tool (`xclip`/`wl-paste`/`pngpaste`) or by reading a file path. Over SSH on a headless VPS there is no X11/Wayland display, so `xclip` fails. Text travels fine over **OSC 52** (which Ghostty supports), but OSC 52 has no way to carry a MIME type, so images need **Kitty's OSC 5522 extension**.
- **Current native status (June 2026):**
  - **Ghostty 1.3.0** (released March 9, 2026 — "6 months of work with changes from 180 contributors over 2,858 commits"; latest is the 1.3.1 patch from March 13, 2026) only *parses but does not implement* OSC 5522 — verbatim 1.3.0 changelog: **"vt: Parse (but do not implement) Kitty clipboard protocol (OSC 5522). #10560."** **No native image-paste-over-SSH in any released Ghostty.** A separate local bug (issue #11444) makes even *local* Cmd+V image paste into Claude Code in Ghostty fail after 2 pastes per session (Warp and iTerm2 handle unlimited pastes).
  - **Claude Code:** the OSC 52/5522-over-SSH request (issue #42712, opened April 2, 2026) was **closed as "not planned"**; the duplicate #47519 also closed. The blocker is a race condition described verbatim in the issue: *"Claude Code spawns xclip as a subprocess that reads from /dev/tty. But Claude Code (a TUI app) also reads from the terminal. The response bytes get split between the two readers. The race condition is unfixable from a subprocess."*
- **What actually works today — bridge tools** (all funnel the image to a remote file path that Claude Code's Read tool auto-attaches; all use `pngpaste` for the macOS clipboard read — `brew install pngpaste`):
  - **cc-clip** (`ShunmeiCho/cc-clip`, MIT) — **most seamless.** Uses an SSH **RemoteForward reverse tunnel + a transparent `xclip` shim**, so Ctrl+V pastes images directly with no per-image command. Works with Claude Code, Codex CLI, and opencode; supports macOS + Windows; also wires desktop notifications. Three commands: `cc-clip setup myserver`, `cc-clip connect myserver`, `cc-clip doctor --host myserver`. (Codex CLI needs the `--codex` flag, which installs Xvfb on the remote because Codex reads X11 directly via the `arboard` crate instead of shelling out to xclip.)
  - **clipssh** (`samuellawrentz/clipssh`, MIT, March 2026) — **simplest.** A shell script, no daemon: `clipssh user@server` uploads the clipboard PNG to `/tmp/clipboard-<ts>.png` (mode 0600) via SSH and copies the remote path back to your clipboard to paste. Install: `brew install pngpaste` then `curl -fsSL https://raw.githubusercontent.com/samuellawrentz/clipssh/main/install.sh | bash`. Set `export CLIPSSH_HOST=user@server` to drop the argument.
  - **claude-ssh-image-skill** (`AlexZeitler/claude-ssh-image-skill`) — a Go **ccimgd** daemon on the Mac (serves clipboard PNG as base64 over TCP 9998) + **ccimg** client on the VPS (reached via SSH reverse tunnel) + a `/paste-image` Claude Code skill in `~/.claude/commands/` that runs `ccimg` and Reads the path.
- **Lower-tech fallbacks (rely on the same path-attachment behavior):**
  - **Syncthing-synced screenshot folder:** point macOS screenshots at a folder Syncthing mirrors to the VPS; reference the path in Claude Code. Most "set-and-forget."
  - **Tailscale Taildrop:** right-click → share screenshot to the VPS (public alpha; only between your own devices, not tagged nodes; must enable "Send Files" in the admin console and the macOS Sharing extension). Manual but encrypted P2P. Also scriptable: `tailscale file cp screenshot.png myvps:`.
- **Recommendation:** Install **cc-clip** for transparent Ctrl+V if you paste often; keep **clipssh** as a zero-daemon fallback; and set up a **Syncthing screenshot folder** as the always-works safety net.

## Details

### Connectivity fabric: Tailscale under everything
Tailscale is a WireGuard-based mesh VPN that gives every device a stable `100.x` IP and a **MagicDNS** name, with mostly peer-to-peer connections and zero firewall config. It is **free for personal use** — and as of Tailscale's **April 8, 2026 pricing change, the Personal plan supports up to 6 users with *unlimited* devices** (the old 100-device cap was removed). Practical payoffs for this setup:
- **MagicDNS** means `ssh myvps` works from anywhere regardless of changing IPs/NAT — ideal for laptop↔VPS.
- **Tailscale SSH** can take over port 22 on the tailnet and authenticate via your tailnet identity + ACLs, eliminating `authorized_keys` management and using auto-expiring WireGuard keys. Trade-off: it's a different trust model (identity-based), and Tailscale SSH lacks built-in session recording unless you deploy recorder nodes; use **check mode** for high-risk (root) connections. Many practitioners keep **plain OpenSSH bound to the Tailscale IP** (`ListenAddress 100.x.y.z`, `PermitRootLogin no`, `PasswordAuthentication no`, `KbdInteractiveAuthentication no`) so the public internet can't even reach port 22 — this is a strong 2026 baseline and immediately silences the brute-force noise in auth logs.
- **Taildrop** for ad-hoc encrypted file/screenshot transfer between your own devices (`tailscale file cp`), though on Linux receiving requires care (`tailscale file get`; avoid blindly running it as root, which can overwrite files via symlink tricks).
- Security note: Tailscale's coordination server is the one piece you don't control; enable **Tailnet Lock** to require physical device approval before new nodes join, set key-expiry/re-auth intervals, and review the published security bulletins (Tailscale shipped several control-plane fixes in late 2025/early 2026).

### Terminal multiplexing + flaky connections
- **tmux** is the recommended base for remote-first work: mature, scriptable, battle-tested session persistence so your Claude Code / build sessions survive disconnects. Use `tmux new-session -A -s dev` to attach-or-create. SSH is just transport; tmux preserves the process tree independently of any single connection.
- **Zellij** is the modern, discoverable alternative (on-screen keybinding hints, floating/pinned panes, KDL config, sessions persist with zero config) — great on workstations, slightly heavier to install on older Ubuntu (may need a static binary). For pure remote SSH persistence, tmux remains the safer pick (more mature session management, better Neovim integration, more battle-tested).
- **mosh** solves flaky/roaming links. Per the Mosh USENIX ATC '12 paper (Winstein & Balakrishnan), **on a 29% packet-loss link Mosh cut average response time by ~50×, from 16.8 s to 0.33 s vs SSH; over commercial 3G, median keystroke response latency was under 5 ms with Mosh vs 503 ms with SSH.** It survives Wi-Fi↔cellular switches and laptop sleep. Pair it with tmux (mosh handles the transport; tmux handles session state). **Caveat: mosh has no scrollback** (it syncs only the visible screen), so always run tmux/zellij inside it.

### Remote development options
- **VS Code Remote-SSH** runs a server on the VPS and gives the full editor/extension experience over SSH — the most mature option, and it pairs with the **Image Paste for Remote SSH (macOS)** marketplace extension that saves clipboard screenshots to `/tmp/screenshots/` and pastes the path (handy for Claude Code in VS Code's terminal).
- **devcontainers** give reproducible, isolated toolchains via `devcontainer.json`; supported first-class by VS Code and (via Gateway/SSH) JetBrains.
- **JetBrains Gateway** connects a local JetBrains IDE to a remote backend over SSH (no Community Edition support).
- For this workflow, VS Code Remote-SSH (or just terminal + tmux) is the path of least resistance; devcontainers are worth it if you want per-project reproducibility across the different Ubuntu versions.

### Shell history, shell, and modern CLI
- **atuin** replaces the flat history file with a SQLite DB plus **end-to-end-encrypted sync** across all machines, with a rich Ctrl-R search filterable by host/dir/exit-code/duration. Self-host the open-source sync server (Docker/Postgres or SQLite) so history never leaves your infrastructure, or use the hosted service (still E2E-encrypted — the server only ever sees ciphertext). Set `filter_mode = "host"` if you don't want every machine's history intermixed, and use `history_filter` regexes to keep secrets (e.g. `export AWS_SECRET_ACCESS_KEY=...`) out of the DB.
- **Shell:** zsh (macOS default) or fish; keep it consistent across machines via chezmoi. Add modern CLI tools (ripgrep, fd, bat, eza, zoxide, fzf, starship) and template their install per-OS in chezmoi `run_onchange_` scripts.

### Secrets management
- **1Password CLI (`op`)** integrates directly with chezmoi templates (`onepasswordRead "op://vault/item/field"`) so secrets are fetched at apply-time and never stored in the dotfiles repo — best if you already use 1Password. (Pass `vault`/`account` for performance and multi-account correctness; note 1Password Connect/Service-Account modes can't span multiple accounts.)
- **sops + age** is the strong file-based alternative: encrypt YAML/JSON/`.env` values (keys stay readable), commit ciphertext to git, decrypt at runtime; store the age private key in 1Password and pull it onto new machines (`op read "op://Private/SOPS AGE Key/private_key" > ~/.config/sops/age/keys.txt && chmod 600`). Good for project/repo secrets and homelab/GitOps; supports per-path keys via `.sops.yaml` creation rules.
- Cloud-style options (Doppler, Infisical) exist but are overkill for a solo multi-VPS setup.

### Backups
- Code is protected by git remotes. For non-repo data, add a real backup (not just sync — sync propagates deletions): **restic** or **borg** to object storage, plus Syncthing file-versioning for accidental-deletion recovery. The atuin DB and chezmoi repo should both be pushed to remotes.

## Recommendations (prioritized)

**Stage 1 — Foundation (do this week, low risk, high payoff):**
1. **Install Tailscale** on the laptop and every VPS; enable MagicDNS. Bind OpenSSH to the Tailscale IP (or enable Tailscale SSH) and disable public port 22, password auth, and root login. Enable Tailnet Lock.
2. **Adopt tmux** (`tmux new-session -A -s dev` alias) on all VPSs, and **mosh** for connecting. Always launch Claude Code inside tmux so sessions survive drops.
3. **Set up atuin** with a self-hosted (or hosted) E2E-encrypted sync server; set `filter_mode = "host"` and `history_filter`.

**Stage 2 — Configuration management (this month):**
4. **Migrate dotfiles Stow → chezmoi**, converting OS-varying files to templates and moving secrets to 1Password or age. Bootstrap each VPS with `chezmoi init --apply <github-user>`.
5. **Rationalize SSH keys:** generate per-device ed25519 keys, move the Mac key into Secure Enclave (Secretive) or 1Password's agent, enroll a backup key everywhere, and clean up `~/.ssh/config` (`IdentitiesOnly yes`, `ProxyJump`, `ControlMaster auto`, `Include config.d/*`).

**Stage 3 — Sync + screenshots (as needed):**
6. **Code:** clone repos fresh on each VPS; sync via git push/pull (peer-to-peer over Tailscale if you want no central remote). **Never sync `.git`.**
7. **Non-repo dirs:** Syncthing for continuous background sync; Mutagen (`ignore: vcs: true`) when actively editing locally and building remotely.
8. **Screenshots into remote Claude Code:** install **cc-clip** (transparent Ctrl+V) as primary; keep **clipssh** as a no-daemon fallback; set up a **Syncthing screenshot folder** as the always-works safety net. Revisit native support when a future Ghostty actually *implements* OSC 5522.

**Benchmarks that would change the recommendation:**
- If **Ghostty ships functional OSC 5522** and Claude Code adds in-process image reads, drop the bridge tools for native paste.
- If you grow to **many users or many servers**, move from per-device keys to an **SSH CA / certificates** (or lean fully on Tailscale SSH ACLs).
- If Mutagen CPU/conflict issues bite, fall back to Syncthing + git.
- If you need reproducible per-project environments across Ubuntu versions, adopt **devcontainers**.

## Caveats
- **Fast-moving area:** Ghostty and Claude Code both ship frequently; the native screenshot-paste situation could change. As of June 2026 it is unsolved natively and Anthropic explicitly closed the request (#42712) as "not planned."
- **Bridge-tool trust:** cc-clip and similar open a loopback tunnel protected by a user-scoped token — don't run them on untrusted shared jump hosts. The cc-clip exact bootstrap installer command could not be fully confirmed; verify against its README (the verified operational interface is `cc-clip setup/connect/doctor`).
- **Tailscale Taildrop is in public alpha** with UI/resume limitations and must be opted-in.
- **Hardware keys can't be backed up** — always enroll a second key, or you can lock yourself out.
- **Sync ≠ backup:** any bidirectional sync (Syncthing/Mutagen) will propagate deletions and corruption; keep independent versioned backups.
- The per-host-vs-per-key debate is genuinely contested; the per-device recommendation reflects the common expert consensus for a solo operator but reasonable people differ.