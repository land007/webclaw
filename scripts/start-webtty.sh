#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/ubuntu}"
export SHELL="${SHELL:-/bin/bash}"
export TERM="${TERM:-xterm-256color}"

if [ -d /home/ubuntu/projects ]; then
  cd /home/ubuntu/projects
else
  cd /home/ubuntu
fi

exec /usr/bin/ttyd \
  -i 0.0.0.0 \
  -p 10008 \
  -W \
  /bin/bash -lc 'cd /home/ubuntu/projects 2>/dev/null || cd /home/ubuntu; exec /bin/bash -il'
