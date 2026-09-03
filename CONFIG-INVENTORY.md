# Config & Home-Dir Inventory

> Audit of `~/.config` and `~` dotdirs: what each is, whether it's worth versioning in
> this dotfiles repo, and how feasible it is to relocate its config into `~/.config` (XDG).
>
> **Guiding split:** *config* (worth versioning) vs *cache / state / data / secrets*
> (never version). Most home dotdirs are the latter — only a handful are dotfiles material.
>
> Items marked *(inferred)* are best-guess identifications and were not verified on disk.
>
> _Last reviewed: 2026-07-01_

---

## `~/.config` — already XDG-clean, all prime dotfiles candidates

| Folder | What it is | Version? | Notes |
|---|---|---|---|
| `git` | Git's XDG config (`config`, `ignore`, attributes) | ✅ | Already there. Version it all. |
| `gh` | GitHub CLI config | ⚠️ | Version `config.yml`; **`hosts.yml` has auth tokens** — exclude. (gh-dash already split this way.) |
| `carapace` | Multi-shell completion engine + custom completion specs | ✅ | Version config + custom specs. |
| `karabiner` | macOS keyboard remapper (Karabiner-Elements), `karabiner.json` | ✅ | High-value — complex modifications are painful to recreate. |
| `ghostty` | Ghostty terminal emulator config | ✅ | Plain-text config, version it. |
| `opencode` | opencode AI-coding CLI config + agents | ⚠️ | Version config/agents; exclude any `auth`/token files. |

## Home dotdirs worth versioning (config-bearing)

| Folder | What it is (1-line) | Version? | → `~/.config`? |
|---|---|---|---|
| `.claude/` | Claude Code: settings, agents, skills, commands, memory, **plus conversation `projects/` + creds** | ⚠️ | `CLAUDE_CONFIG_DIR` env. Version settings/agents/skills/commands; **never** `projects/` or creds. |
| `.agents/` | Likely shared AI-agent definitions (opencode/other) *(inferred)* | ⚠️ | Version if user-authored. |
| `.ssh/` | SSH `config` + **private keys** | ⚠️ | `config` only, carefully; **keys never**. |
| `.continue/` | Continue.dev AI assistant config | ⚠️ | Version `config.json`, strip API keys. |
| `.gemini/` | Google Gemini CLI config | ⚠️ | Version config, exclude auth. |
| `.emacs.d/` | Emacs config (may be leftover — nvim is primary) | ✅ if used | Emacs 27+ reads `~/.config/emacs` natively. |
| `.pip/` | pip config (`pip.conf`) | ✅ | pip reads `~/.config/pip/pip.conf` natively — just move it. |
| `.atuin/` | Atuin shell-history sync: config + **history DB + key** | ⚠️ | Config already lives in `~/.config/atuin`; `~/.atuin` is data/key — don't version. |
| `.jupyter/` `.ipython/` `.matplotlib/` `.streamlit/` | Python tool configs (+ caches/credentials) | ⚠️ | Version the `*config.py`/`config.toml`; skip caches & `credentials.toml`. matplotlib/jupyter honor XDG via env. |
| `.composer/` `.docker/` | PHP Composer / Docker CLI config | ⚠️ | Both carry **auth tokens** — version only non-secret parts. `DOCKER_CONFIG`/`COMPOSER_HOME` relocate them. |

## 🔒 Secrets — never commit these

`.gnupg/` (GPG private keys), `.ssh/` keys, `.john/` (John the Ripper cracked-hash pot),
`.ntfs-for-mac-license-backup/` (Paragon/Tuxera license), `.n8n/` (encryption key + sqlite),
`.browserstack/`, `.gem/credentials`, plus the auth files noted above.

## Skip — cache / state / installs / data (don't version)

| Folder | What it is (1-line) |
|---|---|
| `.DDLocalBackups/` `.DDPreview/` | Disk Drill (CleverFiles recovery) local backup/preview data *(inferred from "DD" prefix)*. |
| `.android/` | Android SDK/ADB state, AVDs, debug keystore (regenerable). |
| `.bash_sessions/` | macOS Terminal session save/restore state. |
| `.bun/` `.yarn/` `.npm/` `.pnpm-state/` `.nvm/` | JS runtime/package-manager installs, caches, global pkgs. Relocate via `BUN_INSTALL`/`NVM_DIR`/etc., don't version. |
| `.cargo/` `.rustup/` | Rust toolchains + registry cache (huge). `CARGO_HOME`/`RUSTUP_HOME` to relocate. |
| `.cache/` `.zcompcache/` `.terminfo/` `.degit/` `.tldrc/` `.sonarlint/` | Pure caches / generated artifacts. |
| `.cagent/` | Docker's `cagent` containerized-agent runtime state. |
| `.codemod/` | Codemod.com CLI (code-transformation tool) cache/state. |
| `.copilot/` | GitHub Copilot CLI auth/state. |
| `.cups/` | Per-user CUPS printing options (machine-specific). |
| `.dropbox/` | Dropbox client local state. |
| `.docker/` | (also above) contexts/buildx state. |
| `.hyper_plugins/` | Hyper terminal installed plugins (deps; `.hyper.js` is the real config). |
| `.idlerc/` | Python IDLE editor config (trivial). |
| `.leon/` | Likely Leon open-source personal-assistant data *(inferred, niche)*. |
| `.llm-checker/` | Tool that benchmarks local LLMs vs. your hardware *(inferred, niche)*. |
| `.lmstudio/` | LM Studio local-LLM GUI + **downloaded models (huge)**. |
| `.local/` | XDG data/state/bin — mostly data; maybe version `~/.local/bin` scripts only. |
| `.oh-my-zsh/` | Oh My Zsh framework clone (a dependency — install via its installer, don't vendor). |
| `.opencode/` | opencode runtime data/state (distinct from `~/.config/opencode`). |
| `.pgadmin/` | pgAdmin GUI state + saved server connections. |
| `.pi/` | Likely the **Pi** agent platform config *(inferred — harness references pi-tools)*. |
| `.postman/` | Postman API client local data (collections usually cloud-synced). |
| `.psychopy3/` `.spss/` | PsychoPy / SPSS — research/stats software config (niche). |
| `.shotgun-sh/` | "Shotgun" code-context prompt-builder state *(inferred, niche)*. |
| `.skiko/` | Skiko (Skia-for-Kotlin/Compose Multiplatform) native-lib cache. |
| `.spotdl/` `.zspotify/` | Spotify downloader caches/config (trivial). |
| `.storybook/` | Storybook config (normally per-project, not global). |
| `.swiftpm/` | Swift Package Manager security/state. |
| `.vscode-insiders/` `.vscode-insiders-shared/` | VS Code Insiders extensions/state (real settings live in `~/Library/Application Support`). |
| `.warp/` | Warp terminal — mostly cloud-synced; little to version locally. |

---

## Practical takeaways

1. **Quick wins to add now:** `karabiner`, `ghostty`, `carapace` from `~/.config` (if not
   already in the repo), plus `.claude/` settings+agents+skills and `.pip/pip.conf` → `~/.config/pip/`.
2. **XDG relocation without app support:** export these in the (versioned) `.zshrc` and the
   dir moves with you —
   `GNUPGHOME`, `CARGO_HOME`, `RUSTUP_HOME`, `NVM_DIR`, `DOCKER_CONFIG`, `COMPOSER_HOME`,
   `BUN_INSTALL`, `ANDROID_USER_HOME`, `CLAUDE_CONFIG_DIR`.
   Some honor XDG natively already (pip, matplotlib, emacs 27+, tealdeer, atuin).
3. **The 90/10 rule:** ~10 of ~60 folders are genuinely dotfiles material; the rest are
   cache/state/secrets that belong in a `.gitignore`, a backup tool, or nowhere.
