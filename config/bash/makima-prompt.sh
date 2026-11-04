# makima-prompt.sh: a bash prompt in the Makima palette, for the foot terminal.
# Source: ~/.config/makima-sway/config/bash/makima-prompt.sh
# Load it from the end of ~/.bashrc with:
#   [ "$TERM" = foot ] && . ~/.config/makima-sway/config/bash/makima-prompt.sh
# Other terminals keep their own prompt.
#
# Colors come from foot's palette (ANSI numbers, ~/.config/foot/foot.ini):
#   31 crimson   33 amber   90 muted (bright black)
#
# Looks like:  user@host ~/some/path ❯
#   user@host in crimson, the path in amber, ❯ muted (crimson if the last command failed)

# Save the last command's exit status before anything else in PROMPT_COMMAND runs
PROMPT_COMMAND="_makima_status=\$?${PROMPT_COMMAND:+; $PROMPT_COMMAND}"

PS1='\[\e[1;31m\]\u@\h\[\e[0m\] \[\e[33m\]\w\[\e[0m\] \[\e[$(( _makima_status ? 31 : 90 ))m\]❯\[\e[0m\] '
