#!/bin/sh
# bead's installer. In a graphical session it opens a window (installer/, a
# Quickshell config driving strand); otherwise, or with --tui, strand's
# terminal installer runs.
#   ./install.sh            install (a window, or the terminal)
#   ./install.sh --tui      the terminal installer, even in a graphical session
#   ./install.sh --dry-run  look around without changing anything (terminal)
#   ./install.sh --yes ...  no questions (terminal; see strand --help)
set -eu
cd "$(dirname "$0")"
if ! command -v pacman >/dev/null; then
    echo "bead's installer supports Arch-based systems (pacman) only." >&2
    exit 1
fi
case " $* " in *" --yes "*) quiet=--noconfirm ;; *) quiet= ;; esac

# the window, when there's a screen to show it on and nothing asks otherwise
gui=
if [ -n "${WAYLAND_DISPLAY:-}" ]; then
    case " $* " in *" --tui "*|*" --yes "*|*" --dry-run "*|*" -n "*) ;; *) gui=1 ;; esac
fi
# drop --tui: it's this script's, not strand's
for a in "$@"; do shift; [ "$a" = --tui ] || set -- "$@" "$a"; done

if [ -n "$gui" ] && ! command -v qs >/dev/null; then
    # the window is drawn by Quickshell, which bead needs anyway: install it first
    if pacman -Si quickshell >/dev/null 2>&1; then
        echo "Installing Quickshell first, for the installer's window (sudo asks for your password)."
        sudo pacman -S --needed quickshell || gui=
    elif command -v paru >/dev/null; then
        echo "Installing Quickshell (AUR) first, for the installer's window."
        paru -S --needed quickshell || gui=
    elif command -v yay >/dev/null; then
        echo "Installing Quickshell (AUR) first, for the installer's window."
        yay -S --needed quickshell || gui=
    else
        echo "Quickshell isn't in your repos and there's no AUR helper: using the terminal installer."
        gui=
    fi
fi

if ! command -v go >/dev/null; then
    echo "strand is written in Go; installing go first (sudo asks for your password)."
    sudo pacman -S --needed $quiet go
fi
(cd strand && go build -trimpath -o strand .)

if [ -n "$gui" ] && command -v qs >/dev/null; then
    echo "Opening the installer…"
    STRAND="$PWD/strand/strand" BEAD_REPO="$PWD" exec qs -p "$PWD/installer"
fi
exec ./strand/strand --repo "$PWD" "$@"
