# Environment
export EDITOR="nvim"
export VISUAL="nvim"
export PATH="$HOME/.local/bin:$PATH"

# SSH agent (user systemd unit)
export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR:-/run/user/$UID}/ssh-agent.socket"

# History (XDG_STATE_HOME)
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
[[ -d "${HISTFILE:h}" ]] || mkdir -p "${HISTFILE:h}"
HISTSIZE=10000
SAVEHIST=10000
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt SHARE_HISTORY

# Completion
autoload -Uz compinit && compinit
zstyle ':completion:*' menu select

# Prompt
setopt PROMPT_SUBST
PROMPT='%F{blue}%n%f@%F{cyan}%m%f %F{yellow}%~%f %(?.%F{green}.%F{red})%#%f '

# Key bindings
bindkey -e
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Plugins
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh 2>/dev/null
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh 2>/dev/null

# Tooling
command -v mise >/dev/null && eval "$(mise activate zsh)"
[[ -r /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
[[ -r /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
command -v gh >/dev/null && eval "$(gh completion -s zsh)"

# Aliases
alias v="nvim"
alias vi="nvim"
alias vim="nvim"
alias ls="eza"
alias ll="eza -lah --git"
alias cat="bat"
alias grep="rg"
alias find="fd"
alias g="git"
alias gst="git status"
alias lzg="lazygit"
alias d="docker"
alias dc="docker compose"
