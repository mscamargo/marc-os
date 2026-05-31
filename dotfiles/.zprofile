# Auto-start X on TTY1
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" == /dev/tty1 ]]; then
    # exec startx
fi
