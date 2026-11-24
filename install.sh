#!/bin/sh
# bead's installer: builds strand (the TUI installer, Go) and runs it.
#   ./install.sh            choose parts and install
#   ./install.sh --dry-run  look around without changing anything
set -eu
cd "$(dirname "$0")"
if ! command -v pacman >/dev/null; then
    echo "bead's installer supports Arch-based systems (pacman) only." >&2
    exit 1
fi
if ! command -v go >/dev/null; then
    echo "strand is written in Go; installing go first (sudo asks for your password)."
    case " $* " in *" --yes "*) quiet=--noconfirm ;; *) quiet= ;; esac
    sudo pacman -S --needed $quiet go
fi
(cd strand && go build -trimpath -o strand .)
exec ./strand/strand --repo "$PWD" "$@"
