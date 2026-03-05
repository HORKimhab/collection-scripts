#!/bin/bash

BASHRC="$HOME/.bashrc"

cp "$BASHRC" "$BASHRC.bak"

echo "Show last folder in prompt instead of full path on terminal."

grep -q "Customize: \\\\w -> \\\\W" "$BASHRC" || cat << 'EOF' >> "$BASHRC"

# Customize: \w -> \W
PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\W\[\033[00m\]\$ '
EOF

source "$BASHRC"

echo "Prompt updated."