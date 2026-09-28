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

# >>> unsnooze >>>
# unsnooze wrappers: route every interactive launch of the CLIs below through
# unsnooze so limit stops are recorded and auto-resumed.
unalias claude 2>/dev/null || true
claude() {
  if [ "${UNSNOOZE_ACTIVE}" = "1" ] || [ ! -f "/usr/lib/node_modules/unsnooze/bin/unsnooze.js" ]; then
    command claude "$@"
    return $?
  fi
  node "/usr/lib/node_modules/unsnooze/bin/unsnooze.js" _run claude "$@"
}
unalias codex 2>/dev/null || true
codex() {
  if [ "${UNSNOOZE_ACTIVE}" = "1" ] || [ ! -f "/usr/lib/node_modules/unsnooze/bin/unsnooze.js" ]; then
    command codex "$@"
    return $?
  fi
  node "/usr/lib/node_modules/unsnooze/bin/unsnooze.js" _run codex "$@"
}
unalias grok 2>/dev/null || true
grok() {
  if [ "${UNSNOOZE_ACTIVE}" = "1" ] || [ ! -f "/usr/lib/node_modules/unsnooze/bin/unsnooze.js" ]; then
    command grok "$@"
    return $?
  fi
  node "/usr/lib/node_modules/unsnooze/bin/unsnooze.js" _run grok "$@"
}
# <<< unsnooze <<<
