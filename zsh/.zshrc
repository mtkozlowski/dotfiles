setopt prompt_subst
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
autoload bashcompinit && bashcompinit
autoload -Uz compinit
compinit

if [[ -f "/opt/homebrew/bin/brew" ]]; then
  # macOS Apple Silicon
    eval "$(/opt/homebrew/bin/brew shellenv)"
    export PATH=$HOME/bin:/opt/homebrew/bin:$PATH
    export XDG_CONFIG_HOME="$HOME/.config"
    export XDG_DATA_DIRS="/opt/homebrew/share:$XDG_DATA_DIRS"
elif [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    # Linux
    echo "Hello Linux!"
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
# zstyle ':completion:*' menu select interactive
zstyle ':completion:*' menu select search
zstyle ':completion:*' list-prompt ''
source <(carapace _carapace)

if command -v brew >/dev/null 2>&1; then
    # Use atuin's DB for inline suggestions so the ghost text and Ctrl-R
    # popup share one source of truth (zsh's $HISTFILE can drift from atuin,
    # e.g. when non-interactive shells append history but skip atuin's hooks).
    ZSH_AUTOSUGGEST_STRATEGY=(atuin)
    source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
bindkey '^w' autosuggest-execute
bindkey '^e' autosuggest-accept
bindkey '^u' autosuggest-toggle
# bindkey '^L' vi-forward-word
bindkey '^k' up-line-or-search
bindkey '^j' down-line-or-search

# You may need to manually set your language environment
export LANG=en_US.UTF-8
export EDITOR="$(command -v nvim || command -v vim)"

alias la=tree

# VI Mode!!!
bindkey jj vi-cmd-mode

# NPM

alias npmst="npm start"
alias npmrd="npm run dev"
alias npmrb="npm run build"

# GIT

alias g='git'
alias ga='git add'
alias gaa='git add --all'
alias gcl='git clone --recurse-submodules'
alias gcmsg='git commit --message'
alias grs='git restore'
alias gst="git status"
alias gpr='git pull --rebase'
alias gpra='git pull --rebase --autostash'
alias gp='git push'
alias gd='git diff'

# Docker
alias dco="docker compose"
alias dps="docker ps"
alias dpa="docker ps -a"
alias dl="docker ps -l -q"
alias dx="docker exec -it"

# Dirs
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias .....="cd ../../../.."
alias ......="cd ../../../../.."
alias ~="cd ~"

# Eza
alias l="eza -l --icons --git -a"
alias lt="eza --tree --level=2 --long --icons --git"
alias ltree="eza --tree --level=2  --icons --git"

# brew
alias bu='brew update'
# bup: upgrade, then summarize what the upgrades introduce (see scripts/brew-upgrade-changes).
# Use `bup --no-notes` or `BREW_NOTES=0 bup` to skip the agent.
bup() { brew-upgrade-changes "$@" }

# macos-only helpers
if [[ "$OSTYPE" == darwin* ]]; then
    function pfd() {
      osascript 2>/dev/null <<EOF
        tell application "Finder"
          return POSIX path of (insertion location as alias)
        end tell
EOF
    }

    function cdf() {
      cd "$(pfd)"
    }

    function quick-look() {
      (( $# > 0 )) && qlmanage -p $* &>/dev/null &
    }
fi

## create dir and cd to it
function vk() { mkdir $1 && cd $_ }

## open yazi with the ability to change the current working directory when exiting
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	command yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
	command rm -f -- "$tmp"
}

# Python
alias py='python3'
alias prepenv='
if [ -d ".venv" ]; then
    rm -rf .venv
fi
python -m venv .venv
source .venv/bin/activate
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
fi
'

# VIM
alias v="nvim"

# Ngrok
if command -v ngrok &>/dev/null; then
	eval "$(ngrok completion)"
fi

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"
command -v starship >/dev/null 2>&1 && eval "$(starship init zsh)"
export STARSHIP_CONFIG=~/.config/starship/starship.toml

if command -v wt >/dev/null 2>&1; then eval "$(command wt config shell init zsh)"; fi

# claude-mv https://curiouslychase.com/posts/rescuing-your-claude-conversations-when-you-rename-projects/
export PATH="$HOME/dotfiles/scripts:$PATH"

# Set up fzf key bindings and fuzzy completion
command -v fzf >/dev/null 2>&1 && source <(fzf --zsh)

export GOPATH="$HOME/go"
export PATH="$GOPATH/bin:$PATH"

[[ -f "$HOME/.atuin/bin/env" ]] && . "$HOME/.atuin/bin/env"
command -v atuin >/dev/null 2>&1 && eval "$(atuin init zsh)"

# Keep the tmux pane title non-empty while sitting at the prompt.
# tmux-resurrect saves a tab-separated line per pane and parses it with
# `IFS=$'\t' read`. Because tab is IFS-whitespace, an EMPTY pane_title field
# collapses, shifts every later field left by one, and the saved cwd is read
# as garbage -> panes get restored in $HOME instead of where you left them.
# Starship doesn't set a title, so a bare prompt has an empty pane_title and
# trips that bug. Setting the title to the current dir keeps the field
# populated. (Local fix in tmux-resurrect: tmux-plugins/tmux-resurrect#570 —
# remove this once that's merged and the plugin is updated.)
if [[ -n "$TMUX" ]]; then
	autoload -Uz add-zsh-hook
	_tmux_pane_title() { print -Pn '\e]2;%~\a'; }
	add-zsh-hook precmd _tmux_pane_title
fi

# Per-machine overrides (not tracked in dotfiles). See .zshrc.local.example.
[[ -f "$ZDOTDIR/.zshrc.local" ]] && source "$ZDOTDIR/.zshrc.local"
