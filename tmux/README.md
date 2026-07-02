# ~/.config/tmux/tmux.conf

## Install
Once everything has been installed it's time to run TPM, install first:
```bash
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

## Run
`Ctrl+I`

## Key bindings

### `prefix + ?` — searchable keybindings

Opens an fzf popup listing all key bindings (via `scripts/tmux-keys`). Fuzzy-search
by key, description, or command. `Enter` runs the selected binding; `Ctrl-Y` copies
the key combo to the tmux buffer and the system clipboard (`set-buffer -w`, OSC 52).
Descriptions come from binding `-N` notes where
present, otherwise the raw command.
