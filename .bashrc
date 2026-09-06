#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

export BLOCK_SIZE=si

alias ls='ls --color=auto --si'
alias grep='grep --color=auto'
alias df='df --si'
alias du='du --si'
# PS1='[\u@\h \W]\$ '


# Added by Antigravity CLI installer
export PATH="/home/ELECTRO/.local/bin:$PATH"
