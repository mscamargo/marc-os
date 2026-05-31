# Environment
export EDITOR="nvim"
export VISUAL="nvim"
export PATH="$HOME/.local/bin:$PATH"

# History
HISTFILE="$HOME/.zsh_history"
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

# Aliases
alias v="nvim"
alias vi="nvim"
alias vim="nvim"
alias ls="ls --color=auto"
alias ll="ls -lah"
