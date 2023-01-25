#!/bin/bash

#
# This script should be run via curl:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# or via wget:
#   sh -c "$(wget -qO- https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
# or via fetch:
#   sh -c "$(fetch -o - https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
#
# As an alternative, you can first download the install script and run it afterwards:
#   wget https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh
#   sh install.sh
#
# You can tweak the install behavior by setting variables when running the script. For
# example, to change the path to the Oh My Zsh repository:
#   ZSH=~/.zsh sh install.sh
#
# Respects the following environment variables:
#   ZSH     - path to the Oh My Zsh repository folder (default: $HOME/.oh-my-zsh)
#   REPO    - name of the GitHub repo to install from (default: ohmyzsh/ohmyzsh)
#   REMOTE  - full remote URL of the git repo to install (default: GitHub via HTTPS)
#   BRANCH  - branch to check out immediately after install (default: master)
#
# Other options:
#   CHSH       - 'no' means the installer will not change the default shell (default: yes)
#   RUNZSH     - 'no' means the installer will not run zsh after the install (default: yes)
#   KEEP_ZSHRC - 'yes' means the installer will not replace an existing .zshrc (default: no)
#
# You can also pass some arguments to the install script to set some these options:
#   --skip-chsh: has the same behavior as setting CHSH to 'no'
#   --unattended: sets both CHSH and RUNZSH to 'no'
#   --keep-zshrc: sets KEEP_ZSHRC to 'yes'
# For example:
#   sh install.sh --unattended
# or:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
#
set -e

OHMYZSH=$( cd "$(dirname "$0")" ; pwd )

# Make sure important variables exist if not already defined
#
# $USER is defined by login(1) which is not always executed (e.g. containers)
# POSIX: https://pubs.opengroup.org/onlinepubs/009695299/utilities/id.html
USER=${USER:-$(id -u -n)}
# $HOME is defined at the time of login, but it could be unset. If it is unset,
# a tilde by itself (~) will not be expanded to the current user's home directory.
# POSIX: https://pubs.opengroup.org/onlinepubs/009696899/basedefs/xbd_chap08.html#tag_08_03
HOME="${HOME:-$(getent passwd $USER 2>/dev/null | cut -d: -f6)}"
# macOS does not have getent, but this works even if $HOME is unset
HOME="${HOME:-$(eval echo ~$USER)}"


# Track if $ZSH was provided
custom_zsh=${ZSH:+yes}

# Default settings
ZSH="${ZSH:-$HOME/.oh-my-zsh}"
REPO=${REPO:-ohmyzsh/ohmyzsh}
REMOTE=${REMOTE:-https://github.com/${REPO}.git}
BRANCH=${BRANCH:-master}

# Other options
CHSH=${CHSH:-yes}
RUNZSH=${RUNZSH:-yes}
KEEP_ZSHRC=${KEEP_ZSHRC:-no}


command_exists() {
  command -v "$@" >/dev/null 2>&1
}

user_can_sudo() {
  # Check if sudo is installed
  command_exists sudo || return 1
  # The following command has 3 parts:
  #
  # 1. Run `sudo` with `-v`. Does the following:
  #    • with privilege: asks for a password immediately.
  #    • without privilege: exits with error code 1 and prints the message:
  #      Sorry, user <username> may not run sudo on <hostname>
  #
  # 2. Pass `-n` to `sudo` to tell it to not ask for a password. If the
  #    password is not required, the command will finish with exit code 0.
  #    If one is required, sudo will exit with error code 1 and print the
  #    message:
  #    sudo: a password is required
  #
  # 3. Check for the words "may not run sudo" in the output to really tell
  #    whether the user has privileges or not. For that we have to make sure
  #    to run `sudo` in the default locale (with `LANG=`) so that the message
  #    stays consistent regardless of the user's locale.
  #
  ! LANG= sudo -n -v 2>&1 | grep -q "may not run sudo"
}

# The [ -t 1 ] check only works when the function is not called from
# a subshell (like in `$(...)` or `(...)`, so this hack redefines the
# function at the top level to always return false when stdout is not
# a tty.
if [ -t 1 ]; then
  is_tty() {
    true
  }
else
  is_tty() {
    false
  }
fi

# This function uses the logic from supports-hyperlinks[1][2], which is
# made by Kat Marchán (@zkat) and licensed under the Apache License 2.0.
# [1] https://github.com/zkat/supports-hyperlinks
# [2] https://crates.io/crates/supports-hyperlinks
#
# Copyright (c) 2021 Kat Marchán
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
supports_hyperlinks() {
  # $FORCE_HYPERLINK must be set and be non-zero (this acts as a logic bypass)
  if [ -n "$FORCE_HYPERLINK" ]; then
    [ "$FORCE_HYPERLINK" != 0 ]
    return $?
  fi

  # If stdout is not a tty, it doesn't support hyperlinks
  is_tty || return 1

  # DomTerm terminal emulator (domterm.org)
  if [ -n "$DOMTERM" ]; then
    return 0
  fi

  # VTE-based terminals above v0.50 (Gnome Terminal, Guake, ROXTerm, etc)
  if [ -n "$VTE_VERSION" ]; then
    [ $VTE_VERSION -ge 5000 ]
    return $?
  fi

  # If $TERM_PROGRAM is set, these terminals support hyperlinks
  case "$TERM_PROGRAM" in
  Hyper|iTerm.app|terminology|WezTerm) return 0 ;;
  esac

  # kitty supports hyperlinks
  if [ "$TERM" = xterm-kitty ]; then
    return 0
  fi

  # Windows Terminal also supports hyperlinks
  if [ -n "$WT_SESSION" ]; then
    return 0
  fi

  # Konsole supports hyperlinks, but it's an opt-in setting that can't be detected
  # https://github.com/ohmyzsh/ohmyzsh/issues/10964
  # if [ -n "$KONSOLE_VERSION" ]; then
  #   return 0
  # fi

  return 1
}

# Adapted from code and information by Anton Kochkov (@XVilka)
# Source: https://gist.github.com/XVilka/8346728
supports_truecolor() {
  case "$COLORTERM" in
  truecolor|24bit) return 0 ;;
  esac

  case "$TERM" in
  iterm           |\
  tmux-truecolor  |\
  linux-truecolor |\
  xterm-truecolor |\
  screen-truecolor) return 0 ;;
  esac

  return 1
}

fmt_link() {
  # $1: text, $2: url, $3: fallback mode
  if supports_hyperlinks; then
    printf '\033]8;;%s\033\\%s\033]8;;\033\\\n' "$2" "$1"
    return
  fi

  case "$3" in
  --text) printf '%s\n' "$1" ;;
  --url|*) fmt_underline "$2" ;;
  esac
}

fmt_underline() {
  is_tty && printf '\033[4m%s\033[24m\n' "$*" || printf '%s\n' "$*"
}

# shellcheck disable=SC2016 # backtick in single-quote
fmt_code() {
  is_tty && printf '`\033[2m%s\033[22m`\n' "$*" || printf '`%s`\n' "$*"
}

fmt_error() {
  printf '%sError: %s%s\n' "${FMT_BOLD}${FMT_RED}" "$*" "$FMT_RESET" >&2
}

setup_color() {
  # Only use colors if connected to a terminal
  if ! is_tty; then
    FMT_RAINBOW=""
    FMT_RED=""
    FMT_GREEN=""
    FMT_YELLOW=""
    FMT_BLUE=""
    FMT_BOLD=""
    FMT_RESET=""
    return
  fi

  if supports_truecolor; then
    FMT_RAINBOW="
      $(printf '\033[38;2;255;0;0m')
      $(printf '\033[38;2;255;97;0m')
      $(printf '\033[38;2;247;255;0m')
      $(printf '\033[38;2;0;255;30m')
      $(printf '\033[38;2;77;0;255m')
      $(printf '\033[38;2;168;0;255m')
      $(printf '\033[38;2;245;0;172m')
    "
  else
    FMT_RAINBOW="
      $(printf '\033[38;5;196m')
      $(printf '\033[38;5;202m')
      $(printf '\033[38;5;226m')
      $(printf '\033[38;5;082m')
      $(printf '\033[38;5;021m')
      $(printf '\033[38;5;093m')
      $(printf '\033[38;5;163m')
    "
  fi

  FMT_RED=$(printf '\033[31m')
  FMT_GREEN=$(printf '\033[32m')
  FMT_YELLOW=$(printf '\033[33m')
  FMT_BLUE=$(printf '\033[34m')
  FMT_BOLD=$(printf '\033[1m')
  FMT_RESET=$(printf '\033[0m')
}


# shellcheck disable=SC2183  # printf string has more %s than arguments ($FMT_RAINBOW expands to multiple arguments)
print_success() {
  printf '%s         %s__      %s           %s        %s       %s     %s__   %s\n'      $FMT_RAINBOW $FMT_RESET
  printf '%s  ____  %s/ /_    %s ____ ___  %s__  __  %s ____  %s_____%s/ /_  %s\n'      $FMT_RAINBOW $FMT_RESET
  printf '%s / __ \\%s/ __ \\  %s / __ `__ \\%s/ / / / %s /_  / %s/ ___/%s __ \\ %s\n'  $FMT_RAINBOW $FMT_RESET
  printf '%s/ /_/ /%s / / / %s / / / / / /%s /_/ / %s   / /_%s(__  )%s / / / %s\n'      $FMT_RAINBOW $FMT_RESET
  printf '%s\\____/%s_/ /_/ %s /_/ /_/ /_/%s\\__, / %s   /___/%s____/%s_/ /_/  %s\n'    $FMT_RAINBOW $FMT_RESET
  printf '%s    %s        %s           %s /____/ %s       %s     %s          %s....is now installed!%s\n' $FMT_RAINBOW $FMT_GREEN $FMT_RESET
  printf '\n'
  printf '\n'
  printf "%s %s %s\n" "Before you scream ${FMT_BOLD}${FMT_YELLOW}Oh My Zsh!${FMT_RESET} look over the" \
    "$(fmt_code "$(fmt_link ".zshrc" "file://$HOME/.zshrc" --text)")" \
    "file to select plugins, themes, and options."
  printf '\n'
  printf '%s\n' $FMT_RESET
}

main() {
  setup_color
  print_success
  #setup_ohmyzsh
  #setup_zshrc
  #setup_shell
}
main "$@"

echo "----------------------------------------------------------"
echo "                 DEPENDENCY CHECK                         "
echo "----------------------------------------------------------" 

ARH_RELEASE="arch\|Manjaro\|Chakra"
DEB_RELEASE="[Dd]ebian\|[Uu]buntu|[Mm]int|[Kk]noppix"
YUM_RELEASE="rhel\|CentOS\|RED\|Fedora"

ARH_PACKAGE_NAME=(zsh git wget curl terminator bat exa tmux powerline)
DEB_PACKAGE_NAME=(zsh git wget curl terminator bat exa tmux powerline)
YUM_PACKAGE_NAME=(zsh git wget curl terminator bat exa tmux powerline)
MAC_PACKAGE_NAME=(zsh git wget curl terminator bat exa tmux powerline)
BSD_PACKAGE_NAME=(zsh git wget curl terminator bat exa tmux powerline)
PIP_PACKAGE_NAME=(thefuck)

PACAPT="/usr/local/bin/pacapt"
PACAPT_INSTALLED=true
pacapt_install()
{
  if ! [ -x "$(command -v pacapt)" ]; then
    echo "Universal Package Manager(icy/pacapt) Download && Install(need sudo permission)"
    sudo curl https://github.com/icy/pacapt/raw/ng/pacapt -Lo $PACAPT
    sudo chmod 755 $PACAPT
    sudo ln -sv $PACAPT /usr/local/bin/pacman || true
    PACAPT_INSTALLED=false
  fi
  sudo pacapt -Sy
}

arh_install()
{
  sudo pacapt -S --noconfirm  "${ARH_PACKAGE_NAME[@]}"
}
deb_install()
{
  sudo pacapt -S --noconfirm "${DEB_PACKAGE_NAME[@]}"
}
yum_install()
{
  sudo pacapt -S --noconfirm "${YUM_PACKAGE_NAME[@]}"
}
mac_install()
{
  brew update
  brew install "${MAC_PACKAGE_NAME[@]}"

  sudo pip3 install powerline-status
}
bsd_install()
{
  pacapt -S --noconfirm "${BSD_PACKAGE_NAME[@]}"
}

set_brew()
{
  if ! [ -x "$(command -v brew)" ]; then
    echo "Now, Install Brew." >&2

    bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    local BREW_PREFIX
    BREW_PREFIX=$(brew --prefix)
    export PATH=${BREW_PREFIX}/bin:${BREW_PREFIX}/sbin:$PATH
  fi
}

pip_install()
{
  if ! [ -x "$(command -v pip3)" ]; then
    curl https://bootstrap.pypa.io/get-pip.py | sudo python3
  fi
  sudo pip3 install "${PIP_PACKAGE_NAME[@]}"
}
etc_install()
{
  pip_install

  mkdir ~/.zplugin
  git clone https://github.com/zdharma-continuum/zinit.git ~/.zplugin/bin
  curl -L "$OHMYZSH" https://raw.githubusercontent.com/denilsonsa/prettyping/master/prettyping > "$OHMYZSH"/prettyping
  chmod +x "$OHMYZSH"/prettyping
  #if ! [[ "$NO_FONT" == YES ]]; then
  #  "OHMYZSH"/install_font.sh
  #fi
}

if   [[ "$OSTYPE" == "linux-gnu" ]]; then
  RELEASE=$(cat /etc/*release)
  pacapt_install

  ##ARH Package
  if   echo "$RELEASE" | grep ^NAME    | grep Manjaro; then
    arh_install
  elif echo "$RELEASE" | grep ^NAME    | grep Chakra ; then
    arh_install
  elif echo "$RELEASE" | grep ^ID      | grep arch   ; then
    arh_install
  elif echo "$RELEASE" | grep ^ID_LIKE | grep arch   ; then
    arh_install

  ##Deb Package
  elif echo "$RELEASE" | grep ^NAME    | grep Ubuntu ; then
    ubuntu_ver=$(lsb_release -rs)
    if [[ ${ubuntu_ver:0:2} -lt 18 ]]; then
      DEB_PACKAGE_NAME=$( sed -e "s/ack/ack-grep/" <(echo "$DEB_PACKAGE_NAME") )
    fi
    deb_install
  elif echo "$RELEASE" | grep ^NAME    | grep Debian ; then
    deb_install
  elif echo "$RELEASE" | grep ^NAME    | grep Mint   ; then
    deb_install
  elif echo "$RELEASE" | grep ^NAME    | grep Knoppix; then
    deb_install
  elif echo "$RELEASE" | grep ^ID_LIKE | grep debian ; then
    deb_install

  ##Yum Package
  elif echo "$RELEASE" | grep ^NAME    | grep CentOS ; then
    yum_install
  elif echo "$RELEASE" | grep ^NAME    | grep Red    ; then
    yum_install
  elif echo "$RELEASE" | grep ^NAME    | grep Fedora ; then
    yum_install
  elif echo "$RELEASE" | grep ^ID_LIKE | grep rhel   ; then
    yum_install

  else
    echo "OS NOT DETECTED, try to flexible mode.."
    if   echo "$RELEASE" | grep "$ARH_RELEASE" > /dev/null 2>&1; then
      arh_install
    elif echo "$RELEASE" | grep "$DEB_RELEASE" > /dev/null 2>&1; then
      deb_install
    elif echo "$RELEASE" | grep "$YUM_RELEASE" > /dev/null 2>&1; then
      yum_install
    fi
  fi
elif [[ "$OSTYPE" == "darwin"*  ]]; then
  set_brew
  mac_install
elif [[ "$OSTYPE" == "FreeBSD"* ]]; then
  pacapt_install
  bsd_install
elif uname -a | grep FreeBSD      ; then
  pacapt_install
  bsd_install
else
  echo "OS NOT DETECTED, couldn't install packages."
  exit 1;
fi

if [[ "$PACAPT_INSTALLED" == false ]]; then
  sudo rm -rf "$PACAPT"
fi

echo "----------------------------------------------------------"
echo "                    OHMYZSH INSTALL                       "
echo "----------------------------------------------------------" 

#mkdir "$OHMYZSH"/cache
zshrc=~/.zshrc
ohmyzsh=~/.oh-my-zsh
#zshenv=~/.zshenv
#zlogin=~/.zlogin
#zprofile=~/.zprofile
#profile=~/.profile

set_file()
{
  local file=$1
  echo "-------"
  echo "Set $file !!"
  echo ""
  if [ -e "$file" ]; then
    echo "$file found."
    echo "Now Backup.."
    cp -r "$file" "$file"_backup_$(date +"%Y-%m-%d")
    echo ""
  else
    echo "$file not found."
    cp -r $file $HOME/$file
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    #touch "$file"
    #echo "$file is created"
    echo ""
  fi
}
set_file $zshrc
set_file $ohmyzsh
#set_file $zlogin

#echo "source $HOME/.zshrc"         >> $zshrc
#echo "source $BVZSH/BlaCk-Void.zshenv"        >> $zshenv
#echo "source $BVZSH/BlaCk-Void.zlogin"        >> $zlogin
#if [ -e $profile ]; then
#  < $profile tee -a $zprofile
#fi

echo "----------------------------------------------------------"
echo "                  INSTALL FONTS                           "
echo "----------------------------------------------------------" 

necessary()
{
    if   [[ "$OSTYPE" == "linux-gnu" ]]; then
        local fontDir="/usr/share/fonts/"
    elif [[ "$OSTYPE" == "darwin"*  ]] ; then
        local fontDir="/Library/Fonts/"
    elif uname -a | grep FreeBSD       ; then
        local fontDir="/usr/local/share/fonts/"
    else
        echo "OS NOT DETECTED, couldn't install fonts."
        exit 1;
    fi
    cd "$fontDir" || exit
    sudo curl -fLo "Hack Bold Nerd Font Complete.ttf" https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/Hack/Bold/complete/Hack%20Bold%20Nerd%20Font%20Complete.ttf
    sudo curl -fLo "Hack Bold Italic Nerd Font Complete.ttf" https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/Hack/BoldItalic/complete/Hack%20Bold%20Italic%20Nerd%20Font%20Complete.ttf
    sudo curl -fLo "Hack Italic Nerd Font Complete.ttf" https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/Hack/Italic/complete/Hack%20Italic%20Nerd%20Font%20Complete.ttf
    sudo curl -fLo "Hack Regular Nerd Font Complete.ttf" https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/patched-fonts/Hack/Regular/complete/Hack%20Regular%20Nerd%20Font%20Complete.ttf
    sudo chmod 644 Hack*

    if ! [[ "$OSTYPE" == "darwin"*  ]] ; then
      fc-cache -f -v
    fi
    cd "$BVZSH" || exit
}

#cd "$HOME" || exit

echo "--------------------"
echo " INSTALL PLUGINS "
echo ""

if [ -d $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions ]; then
    cd $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions && git pull
else
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
fi

if [ -d $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting ]; then
    cd $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && git pull
else
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
fi

if [ -d $HOME/.oh-my-zsh/custom/plugins/zsh-completions ]; then
    cd $HOME/.oh-my-zsh/custom/plugins/zsh-completions && git pull
else
    git clone https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
fi

if [ -d $HOME/.oh-my-zsh/custom/plugins/zsh-history-substring-search ]; then
    cd $HOME/.oh-my-zsh/custom/plugins/zsh-history-substring-search && git pull
else
    git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
fi

if [ -d $HOME/.fzf ]; then
    cd $HOME/.fzf && git pull
    $HOME/.fzf/install --all --key-bindings --completion --no-update-rc
else
    git clone --depth 1 https://github.com/junegunn/fzf.git $HOME/.fzf
    $HOME/.fzf/install --all --key-bindings --completion --no-update-rc
fi

if [ -d $HOME/.oh-my-zsh/custom/plugins/fzf-tab ]; then
    cd $HOME/.oh-my-zsh/custom/plugins/fzf-tab && git pull
else
git clone --depth 1 https://github.com/Aloxaf/fzf-tab ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-tab
fi

if [ -d $HOME/.oh-my-zsh/custom/plugins/k ]; then
    cd $HOME/.oh-my-zsh/custom/plugins/k && git pull
else
    git clone --depth 1 https://github.com/supercrabtree/k $HOME/.oh-my-zsh/custom/plugins/k
fi

if [ -d $HOME/.marker ]; then
    cd $HOME/.marker && git pull
else
    git clone --depth=1 https://github.com/pindexis/marker ~/.marker && ~/.marker/install.py $HOME/.marker
    echo -e "Installed Marker\n"
fi

if [ -d $HOME/.oh-my-zsh/custom/plugins/zsh-z ]; then
    cd $HOME/.oh-my-zsh/custom/plugins/zsh-z && git pull
else
git clone --depth=1 https://github.com/agkozak/zsh-z ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-z
fi

#INSTALL THEMES
if [ -d $HOME/.oh-my-zsh/custom/themes/powerlevel10k ]; then
    cd $HOME/.oh-my-zsh/custom/themes/powerlevel10k && git pull
else
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $HOME/.oh-my-zsh/custom/themes/powerlevel10k
fi

if [ -d $HOME/.oh-my-zsh/custom/themes/spaceship-prompt ]; then
    cd $HOME/.oh-my-zsh/custom/themes/spaceship-prompt && git pull
else
    git clone --depth=1 https://github.com/spaceship-prompt/spaceship-prompt.git $HOME/.oh-my-zsh/custom/themes/spaceship-prompt
fi

#if [[ $1 == "--cp-hist" ]] || [[ $1 == "-c" ]]; then
#    echo -e "\nCopying bash_history to zsh_history\n"
#    if command -v python &>/dev/null; then
#        wget -q --show-progress https://gist.githubusercontent.com/muendelezaji/c14722ab66b505a49861b8a74e52b274/raw/49f0fb7f661bdf794742257f58950d209dd6cb62/bash-to-zsh-hist.py
#        cat ~/.bash_history | python bash-to-zsh-hist.py >> ~/.zsh_history
#    else
#        if command -v python3 &>/dev/null; then
#            wget -q --show-progress https://gist.githubusercontent.com/muendelezaji/c14722ab66b505a49861b8a74e52b274/raw/49f0fb7f661bdf794742257f58950d209dd6cb62/bash-to-zsh-hist.py
#            cat ~/.bash_history | python3 bash-to-zsh-hist.py >> ~/.zsh_history
#        else
#            echo "Python is not installed, can't copy bash_history to zsh_history\n"
#        fi
#    fi
#else
#    echo -e "\nNot copying bash_history to zsh_history, as --cp-hist or -c is not supplied\n"
#fi

#source ~/.zshrc

echo -e "\nSudo access is needed to change default shell\n"


if chsh -s $(which zsh) && $(which zsh) -i -c 'omz update'; then
    echo -e "Installation Successful, exit terminal and enter a new session"
else
    echo -e "Something is wrong"
fi

exec zsh

exit



