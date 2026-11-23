#!/usr/bin/env bash
# Walk through every variant, like sileo's demo page (bead's Glint).
set -u
t() { glint "$@"; sleep 3.2; }
t success "Saved" -d "Your changes are safe." -t 3s
t error "Upload failed" -d "The server returned 500." -t 3s
t warning "Disk almost full" -d "/mnt/windows is 98% full." -t 3s
t info "Homelab" -d "17 containers, 14 running." -t 3s
t success "Custom icon" -i "★" -d "Any glyph, emoji or image path." -t 3s
glint action "Update ready" -b "Restart" -d "A new version is installed." -t 4s; sleep 0.5
glint promise "Working" --success "All done" -- sleep 2; sleep 3.5
glint confirm "Looks good?" --yes "Yes" -t 6s && echo "you said yes" || echo "no / dismissed"
