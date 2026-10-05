#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if pgrep -x Keystrokes >/dev/null 2>&1 && [[ -d dist/Keystrokes.app ]]; then
  if [[ -d /Applications/Keystrokes.app ]]; then
    open /Applications/Keystrokes.app
  elif [[ -d "$HOME/Applications/Keystrokes.app" ]]; then
    open "$HOME/Applications/Keystrokes.app"
  else
    open "$PWD/dist/Keystrokes.app"
  fi
  exit 0
fi
exec ./scripts/build.sh --run
