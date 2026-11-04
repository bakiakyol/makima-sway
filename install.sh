#!/bin/sh
# install.sh: links the makima-sway configs into place (symlinks).
#
#   ./install.sh            create the links
#   ./install.sh -n         dry run: show what would happen, change nothing
#   ./install.sh --cursor   also build the crimson mouse cursor (Makima-Crimson)
#
# What it does:
#   ~/.config/makima-sway  -> this repo (configs reach the repo through this fixed path)
#   ~/.config/sway/config, waybar, foot, fuzzel, swaylock  -> files in the repo
#   <firefox profile>/chrome/userChrome.css -> palette for the tab strip (+ one pref in user.js)
#   ~/.local/bin/*         -> scripts in the repo's bin/
#   ~/.config/systemd/user/battery-warning.{service,timer} -> low battery popup, enabled
#
# An existing file, or a link pointing somewhere else, is never deleted: it is moved
# next to itself as "<name>.bak-makima-<date>". Links that are already correct are left alone.
# It does not install packages and does not touch ~/.bash_profile or ~/.bashrc (see the README).

set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
STAMP=$(date +%Y%m%d-%H%M%S)
DRY_RUN=0
CURSOR=0

for arg in "$@"; do
	case "$arg" in
	-n | --dry-run) DRY_RUN=1 ;;
	--cursor) CURSOR=1 ;;
	-h | --help) sed -n '2,18p' "$0"; exit 0 ;;
	*) echo "unknown option: $arg (help: ./install.sh -h)" >&2; exit 1 ;;
	esac
done

run() {
	if [ "$DRY_RUN" = 1 ]; then echo "  [dry-run] $*"; else "$@"; fi
}

# link SOURCE TARGET: make TARGET a symlink to SOURCE
link() {
	source=$1; target=$2
	if [ -L "$target" ] && [ "$(readlink "$target")" = "$source" ]; then
		echo "  ok       $target"
		return
	fi
	run mkdir -p "$(dirname "$target")"
	if [ -e "$target" ] || [ -L "$target" ]; then
		echo "  backup   $target -> $target.bak-makima-$STAMP"
		run mv "$target" "$target.bak-makima-$STAMP"
	fi
	echo "  link     $target -> $source"
	run ln -s "$source" "$target"
}

echo "makima-sway: $REPO"
[ "$DRY_RUN" = 1 ] && echo "(dry run: nothing will change)"

echo
echo "Repo:"
link "$REPO" "$HOME/.config/makima-sway"

# From here on, links go through this fixed path. If you move the repo, run ./install.sh
# again from its new place: only this one link changes, all the others stay valid.
M="$HOME/.config/makima-sway"

echo
echo "Configs:"
link "$M/config/sway/config"         "$HOME/.config/sway/config"
link "$M/config/waybar/config.jsonc" "$HOME/.config/waybar/config.jsonc"
link "$M/config/waybar/style.css"    "$HOME/.config/waybar/style.css"
link "$M/config/foot/foot.ini"       "$HOME/.config/foot/foot.ini"
link "$M/config/fuzzel/fuzzel.ini"   "$HOME/.config/fuzzel/fuzzel.ini"
link "$M/config/swaylock/config"     "$HOME/.config/swaylock/config"
# No link for dunst: Sway starts it directly with "dunst --config ~/.config/makima-sway/...",
# so a dunst setup you use on another desktop (like i3) stays untouched.

echo
echo "Firefox (tab strip colors):"
# Firefox 147+ keeps profiles in ~/.config/mozilla/firefox, older ones in ~/.mozilla/firefox.
# The profile Firefox actually opens is the "Default=" of an [Install...] section.
ff_profile=
for ff_dir in "$HOME/.config/mozilla/firefox" "$HOME/.mozilla/firefox"; do
	[ -f "$ff_dir/profiles.ini" ] || continue
	ff_rel=$(awk -F= '/^\[Install/ { inst = 1; next } /^\[/ { inst = 0 } inst && $1 == "Default" { print $2; exit }' "$ff_dir/profiles.ini")
	case "$ff_rel" in
	"") continue ;;
	/*) ff_profile=$ff_rel ;;
	*) ff_profile="$ff_dir/$ff_rel" ;;
	esac
	[ -d "$ff_profile" ] && break
	ff_profile=
done
if [ -z "$ff_profile" ]; then
	echo "  skipped  no Firefox profile found (open Firefox once, then run ./install.sh again)"
else
	link "$M/config/firefox/userChrome.css" "$ff_profile/chrome/userChrome.css"
	# Firefox ignores userChrome.css unless this pref is on. Only appended, never rewritten.
	ff_pref='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
	if [ -f "$ff_profile/user.js" ] && grep -qF "$ff_pref" "$ff_profile/user.js"; then
		echo "  ok       $ff_profile/user.js"
	else
		echo "  append   userChrome.css pref -> $ff_profile/user.js"
		if [ "$DRY_RUN" = 0 ]; then
			printf '\n// makima-sway: let Firefox read chrome/userChrome.css\n%s\n' "$ff_pref" >>"$ff_profile/user.js"
		fi
	fi
	echo "  note     restart Firefox to see the change"
fi

echo
echo "Scripts (~/.local/bin):"
for script in "$REPO"/bin/*; do
	# Only executable files (no folders, no stray files like __pycache__)
	[ -f "$script" ] && [ -x "$script" ] || continue
	link "$M/bin/$(basename "$script")" "$HOME/.local/bin/$(basename "$script")"
done

echo
echo "Battery warning (systemd user timer):"
link "$M/config/systemd/battery-warning.service" "$HOME/.config/systemd/user/battery-warning.service"
link "$M/config/systemd/battery-warning.timer"   "$HOME/.config/systemd/user/battery-warning.timer"
if ! systemctl --user show-environment >/dev/null 2>&1; then
	echo "  skipped  no systemd user session; run ~/.local/bin/battery-warning every few minutes some other way"
elif systemctl --user is-enabled -q battery-warning.timer 2>/dev/null; then
	echo "  ok       battery-warning.timer is enabled"
else
	echo "  enable   battery-warning.timer"
	run systemctl --user daemon-reload
	run systemctl --user enable --now battery-warning.timer
fi

if [ "$CURSOR" = 1 ]; then
	echo
	echo "Mouse cursor (Makima-Crimson):"
	VERSION=v2.0.7
	URL="https://github.com/ful1e5/Bibata_Cursor/releases/download/$VERSION/Bibata-Modern-Amber.tar.xz"
	SHA256=58b7ac00ed3cb45acb6b917cb9807a553873f1cca5c91348c4abaebe638e5884
	if [ "$DRY_RUN" = 1 ]; then
		echo "  [dry-run] download $URL, recolor to crimson as ~/.local/share/icons/Makima-Crimson"
	else
		TMP=$(mktemp -d)
		trap 'rm -rf "$TMP"' EXIT
		echo "  downloading: $URL"
		curl -fsSL -o "$TMP/amber.tar.xz" "$URL"
		# Only use the exact file this setup was made with
		if ! echo "$SHA256  $TMP/amber.tar.xz" | sha256sum -c --status; then
			echo "  error: the downloaded file doesn't match the expected checksum, not using it" >&2
			exit 1
		fi
		tar -xf "$TMP/amber.tar.xz" -C "$TMP"
		python3 -I "$REPO/design/recolor-cursor.py" "$TMP/Bibata-Modern-Amber" \
			"$HOME/.local/share/icons/Makima-Crimson" "Makima-Crimson" e22e0e
	fi
fi

# ---------- checks (read only) ----------
echo
echo "Checks:"
# Programs the configs and scripts call. (i3 extras like maim, xclip, i3lock aren't checked.)
missing=
for prog in sway waybar foot fuzzel dunst notify-send swaylock swayidle grim slurp wl-copy \
	brightnessctl wpctl iwctl busctl python3; do
	command -v "$prog" >/dev/null 2>&1 || missing="$missing $prog"
done
if [ -n "$missing" ]; then
	echo "  missing :$missing  (see Requirements in the README)"
else
	echo "  ok       all programs found"
fi
if [ -d "$HOME/.local/share/icons/Makima-Crimson" ]; then
	echo "  ok       cursor theme Makima-Crimson"
elif [ "$CURSOR" = 0 ]; then
	echo "  note     cursor theme Makima-Crimson isn't installed (Sway uses its default cursor)."
	echo "           To build it: ./install.sh --cursor"
fi

echo
if [ "$DRY_RUN" = 1 ]; then
	echo "Dry run finished. To install for real: ./install.sh"
else
	echo "Done. If Sway is running, reload it: Super+Shift+c"
	case ":$PATH:" in
	*":$HOME/.local/bin:"*) ;;
	*) echo "Note: ~/.local/bin is not in your PATH. Add this to ~/.bash_profile: export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
	esac
fi
