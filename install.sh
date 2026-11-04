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
#   ~/.local/bin/*         -> scripts in the repo's bin/
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
	-h | --help) sed -n '2,16p' "$0"; exit 0 ;;
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

# From here on, links go through the fixed path, so moving the repo won't break them.
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
echo "Scripts (~/.local/bin):"
for script in "$REPO"/bin/*; do
	link "$M/bin/$(basename "$script")" "$HOME/.local/bin/$(basename "$script")"
done

if [ "$CURSOR" = 1 ]; then
	echo
	echo "Mouse cursor (Makima-Crimson):"
	VERSION=v2.0.7
	URL="https://github.com/ful1e5/Bibata_Cursor/releases/download/$VERSION/Bibata-Modern-Amber.tar.xz"
	if [ "$DRY_RUN" = 1 ]; then
		echo "  [dry-run] download $URL, recolor to crimson as ~/.local/share/icons/Makima-Crimson"
	else
		TMP=$(mktemp -d)
		trap 'rm -rf "$TMP"' EXIT
		echo "  downloading: $URL"
		curl -fsSL -o "$TMP/amber.tar.xz" "$URL"
		tar -xf "$TMP/amber.tar.xz" -C "$TMP"
		python3 -I "$REPO/design/recolor-cursor.py" "$TMP/Bibata-Modern-Amber" \
			"$HOME/.local/share/icons/Makima-Crimson" "Makima-Crimson" e22e0e
	fi
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
