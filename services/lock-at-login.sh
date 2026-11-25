#!/bin/sh
# services/lock-at-login.sh MODE MARK: exits 0 when bead should lock as it
# starts (services/Lock.qml). Once per login: MARK (in $XDG_RUNTIME_DIR, gone
# at logout) is made the first time, and after that it always says no, so a
# bead restart never locks you out.
#   MODE on: lock; off: don't; auto: lock when this user is logged in by
#   itself (SDDM, LightDM, GDM or greetd autologin, or a getty --autologin),
#   since then nothing asked for a password
# BEAD_ETC (tests only) reads the config files under another root.
mode=$1 mark=$2 etc=${BEAD_ETC:-}
[ -e "$mark" ] && exit 1
mkdir -p "${mark%/*}" && : >"$mark"
case $mode in on) exit 0 ;; off) exit 1 ;; esac
u=$(id -un)

# KEY=USER inside [SECTION] (ini or toml; spaces and quotes ignored)
section() {
	awk -v want="$1" -v key="$2" -v u="$u" '
		/^[ \t]*\[/ { s = $0; gsub(/[ \t]/, "", s); next }
		s == want { l = $0; gsub(/[ \t"]/, "", l); if (l == key "=" u) f = 1 }
		END { exit !f }'
}
cat "$etc"/usr/lib/sddm/sddm.conf.d/*.conf "$etc"/etc/sddm.conf.d/*.conf "$etc"/etc/sddm.conf 2>/dev/null |
	section "[Autologin]" User && exit 0
cat "$etc"/etc/greetd/config.toml 2>/dev/null | section "[initial_session]" user && exit 0
cat "$etc"/etc/lightdm/lightdm.conf "$etc"/etc/lightdm/lightdm.conf.d/*.conf 2>/dev/null |
	section "[Seat:*]" autologin-user && exit 0
gdm="$etc"/etc/gdm/custom.conf
cat "$gdm" 2>/dev/null | section "[daemon]" AutomaticLogin &&
	grep -qsE '^[[:space:]]*AutomaticLoginEnable[[:space:]]*=[[:space:]]*([Tt]rue|1)' "$gdm" && exit 0
cat "$etc"/etc/systemd/system/getty@*.service.d/*.conf 2>/dev/null |
	grep -qE -- "--autologin[= ]+$u([[:space:]]|\$)" && exit 0
exit 1
