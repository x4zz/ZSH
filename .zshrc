### PLUGINS ###
#https://github.com/ogham/exa exa is a modern replacement for ls.
#https://github.com/sharkdp/bat A cat(1) clone with syntax highlighting and Git integration. 
#https://github.com/junegunn/fzf
#https://github.com/zdharma-continuum/zinit

export ZSH="$HOME/.oh-my-zsh"

# need to disable in order for exa ls alias to work
DISABLE_LS_COLORS="true"

# FZF settings
export FZF_BASE="$HOME/.fzf"
export FZF_DEFAULT_COMMAND='rg --hidden --no-ignore --files -g "!.git/"'
export FZF_CTRL_T_COMMAND=$FZF_DEFAULT_COMMAND
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

ZSH_THEME="powerlevel10k/powerlevel10k"
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=244"

plugins=(
  k
  git
  fzf
  fzf-tab
  zsh-z
  sudo
  zsh-completions 
  zsh-autosuggestions
  zsh-syntax-highlighting
  zsh-history-substring-search
)

source $ZSH/oh-my-zsh.sh

# Large history file
HISTSIZE=10000000
SAVEHIST=10000000

# Prevent duplicates in history
setopt hist_ignore_all_dups hist_save_nodups

# Remove hostname:
#prompt_context() {} 

# Aliases:
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

echo '# Install Ruby Gems to ~/gems' >> ~/.bashrc
echo 'export GEM_HOME=$HOME/gems' >> ~/.bashrc
echo 'export PATH=$HOME/gems/bin:$PATH' >> ~/.bashrc

# My aliases:
alias lg='ll -a | grep '
alias hg='history | grep '
alias hv='history | vim -'
alias copy='xsel -ib'
alias paste='xsel --clipboard'
alias vimclipboard='paste | vim -'
alias mv="mv -v"
alias rm="rm -vi"
alias cp="cp -v"
alias install="sudo apt install "
alias update="sudo apt update"

alias ls="exa --icons"
alias ll="exa -l -g --icons"
alias lt="exa --tree --icons -a -I '.git|__pycache__|.mypy_cache|.ipynb_checkpoints'"
alias fp="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
alias gt='starship toggle gcloud disabled'
# My functions:
mkdircd () {
    mkdir "$@"
    if [ "$1" = "-p" ]; then
        cd "$2"
    else
        cd "$1"
    fi
}

pathtofile () {
  case "$1" in
    /*) printf '%s\n' "$1";;
    *) printf '%s\n' "$PWD/$1";;
  esac
}

# open file by text
# sudo apt-get install silversearcher-ag
# git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf # ~/.fzf/installCopy
vg() {
  local file
  local line

  read -r file line <<<"$(ag --nobreak --noheading $@ | fzf -0 -1 | awk -F: '{print $1, $2}')"

  if [[ -n $file ]]
  then
     vim $file +$line
  fi
}

# open file by name
vf() {
  local files
  IFS=$'\n' files=($(fzf-tmux --query="$1" --multi --select-1 --exit-0))
  [[ -n "$files" ]] && ${EDITOR:-vim} "${files[@]}"
}

# interactive cd
function cd() {
    if [[ "$#" != 0 ]]; then
        builtin cd "$@";
        return
    fi
    while true; do
        local lsd=$(echo ".." && ls -p | grep '/$' | sed 's;/$;;')
        local dir="$(printf '%s\n' "${lsd[@]}" |
            fzf --reverse --preview '
                __cd_nxt="$(echo {})";
                __cd_path="$(echo $(pwd)/${__cd_nxt} | sed "s;//;/;")";
                echo $__cd_path;
                echo;
                ls -p --color=always "${__cd_path}";
        ')"
        [[ ${#dir} != 0 ]] || return 0
        builtin cd "$dir" &> /dev/null
    done
}

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
