#!/usr/bin/env python3
"""recolor-cursor: recolors an Xcursor theme to any hex color.

Usage:
	python3 design/recolor-cursor.py SOURCE_THEME TARGET_DIR "Theme Name" e22e0e
	(the color can also be written as "#e22e0e")

Example (the Makima cursor, from Bibata Modern Amber):
	python3 design/recolor-cursor.py ~/Downloads/Bibata-Modern-Amber \
		~/.local/share/icons/Makima-Crimson "Makima-Crimson" e22e0e

What it does:
	Xcursor files hold one ARGB image per size and per animation frame.
	For every pixel, the script:
	- moves colored pixels (high saturation, i.e. the theme's amber body) to the target color.
	  Light and shade are kept, so the cursor doesn't look like flat paint.
	- leaves black, white, and gray pixels (outlines, highlights) alone.
	Symlinks (other names for the same cursor) are copied as they are.

Safe to re-run: the new theme is built in a temporary folder next to TARGET_DIR and only
replaces the old one once it's complete. If anything fails, the old theme stays as it was.
An existing TARGET_DIR is only replaced if it looks like a theme this script made.

Uses only the Python standard library.
"""

import colorsys
import os
import shutil
import struct
import sys
from collections import Counter

IMAGE_TYPE = 0xFFFD0002   # chunk type of an "image" in the Xcursor format


class Failure(Exception):
	"""Something is wrong with the input; the message is shown to the user."""


def read_images(data, path):
	"""List the image chunks in an Xcursor file as (pixel offset, width, height)."""
	if data[:4] != b"Xcur":
		raise Failure(f"{path}: not an Xcursor file")
	try:
		_, _, count = struct.unpack_from("<III", data, 4)
		images = []
		for i in range(count):
			kind, _, offset = struct.unpack_from("<III", data, 16 + i * 12)
			if kind == IMAGE_TYPE:
				# Chunk header: size, type, subtype, version, width, height, xhot, yhot, delay
				width, height = struct.unpack_from("<II", data, offset + 16)
				if offset + 36 + width * height * 4 > len(data):
					raise struct.error("image runs past the end of the file")
				images.append((offset + 36, width, height))
	except struct.error:
		raise Failure(f"{path}: broken Xcursor file")
	return images


def recolor_pixel(argb, target_h, l_ratio, s_ratio, cache):
	"""Recolor one ARGB pixel. Xcursor colors are premultiplied by alpha."""
	if argb in cache:
		return cache[argb]
	a = argb >> 24
	if a == 0:
		cache[argb] = argb
		return argb
	r = ((argb >> 16) & 0xFF) * 255 / a
	g = ((argb >> 8) & 0xFF) * 255 / a
	b = (argb & 0xFF) * 255 / a
	h, l, s = colorsys.rgb_to_hls(min(r, 255) / 255, min(g, 255) / 255, min(b, 255) / 255)
	if s < 0.30 or l < 0.08 or l > 0.95:
		# Black / white / gray: leave it
		cache[argb] = argb
		return argb
	l2 = min(1.0, l * l_ratio)
	s2 = min(1.0, s * s_ratio)
	r2, g2, b2 = colorsys.hls_to_rgb(target_h, l2, s2)
	# Premultiply by alpha again
	result = (a << 24) | (round(r2 * a) << 16) | (round(g2 * a) << 8) | round(b2 * a)
	cache[argb] = result
	return result


def find_base_color(files):
	"""Find the theme's main color (the most common saturated color): the amber body."""
	counter = Counter()
	for path in files[:20]:
		data = open(path, "rb").read()
		for offset, width, height in read_images(data, path):
			for (p,) in struct.iter_unpack("<I", data[offset:offset + width * height * 4]):
				if p >> 24 == 0xFF:
					r, g, b = (p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF
					if colorsys.rgb_to_hls(r / 255, g / 255, b / 255)[2] > 0.5:
						counter[(r, g, b)] += 1
	if not counter:
		raise Failure("no colored pixels found in the source theme, nothing to recolor")
	return counter.most_common(1)[0][0]


def parse_color(color):
	"""'e22e0e' or '#e22e0e' -> 'e22e0e'."""
	color = color.strip().lstrip("#").lower()
	if len(color) != 6 or any(c not in "0123456789abcdef" for c in color):
		raise Failure(f"color must be 6 hex digits like e22e0e, got {color!r}")
	return color


def check_paths(source, target):
	"""Refuse anything that could delete the wrong folder."""
	source_cursors = os.path.join(source, "cursors")
	if not os.path.isdir(source_cursors) or not os.listdir(source_cursors):
		raise Failure(f"{source} has no cursors/ folder with cursor files in it")
	if source == target or target.startswith(source + os.sep) or source.startswith(target + os.sep):
		raise Failure("source and target must be separate folders, not the same or inside each other")
	if os.path.lexists(target):
		# Only replace a theme made by this script: cursors/ + index.theme with our comment
		index = os.path.join(target, "index.theme")
		ours = (os.path.isdir(target) and not os.path.islink(target)
			and set(os.listdir(target)) <= {"cursors", "index.theme"}
			and os.path.isfile(index) and ", recolored to #" in open(index).read())
		if not ours:
			raise Failure(f"{target} already exists and wasn't made by this script; "
				"move it away or pick another target")


def build(source_cursors, target, name, color, source_name):
	"""Write the recolored theme into the (new, empty) folder target."""
	tr, tg, tb = (int(color[i:i + 2], 16) / 255 for i in (0, 2, 4))
	target_h, target_l, target_s = colorsys.rgb_to_hls(tr, tg, tb)
	target_cursors = os.path.join(target, "cursors")
	os.makedirs(target_cursors)

	files = sorted(
		os.path.join(source_cursors, f) for f in os.listdir(source_cursors)
		if not os.path.islink(os.path.join(source_cursors, f))
	)
	br, bg, bb = find_base_color(files)
	_, base_l, base_s = colorsys.rgb_to_hls(br / 255, bg / 255, bb / 255)
	l_ratio, s_ratio = target_l / base_l, target_s / base_s
	print(f"source base color: #{br:02x}{bg:02x}{bb:02x}  ->  target: #{color}")

	cache = {}
	for f in sorted(os.listdir(source_cursors)):
		src = os.path.join(source_cursors, f)
		dst = os.path.join(target_cursors, f)
		if os.path.islink(src):
			os.symlink(os.readlink(src), dst)
			continue
		data = bytearray(open(src, "rb").read())
		for offset, width, height in read_images(data, src):
			n = width * height
			pixels = struct.unpack_from(f"<{n}I", data, offset)
			recolored = [recolor_pixel(p, target_h, l_ratio, s_ratio, cache) for p in pixels]
			struct.pack_into(f"<{n}I", data, offset, *recolored)
		open(dst, "wb").write(data)

	with open(os.path.join(target, "index.theme"), "w") as theme:
		theme.write(f"[Icon Theme]\nName={name}\nComment=Based on {source_name}, recolored to #{color}\nInherits=hicolor\n")
	return len(os.listdir(target_cursors))


def main():
	if len(sys.argv) != 5:
		print(__doc__)
		return 1
	source, target, name, color = sys.argv[1:]
	source = os.path.realpath(os.path.expanduser(source))
	target = os.path.abspath(os.path.expanduser(target))
	try:
		color = parse_color(color)
		check_paths(source, target)
		# Build next to the target, then swap it in, so a failure leaves the old theme alone
		os.makedirs(os.path.dirname(target), exist_ok=True)
		tmp = f"{target}.tmp-{os.getpid()}"
		try:
			count = build(os.path.join(source, "cursors"), tmp, name, color, os.path.basename(source))
			if os.path.lexists(target):
				old = f"{target}.old-{os.getpid()}"
				os.rename(target, old)
				os.rename(tmp, target)
				shutil.rmtree(old)
			else:
				os.rename(tmp, target)
		finally:
			if os.path.lexists(tmp):
				shutil.rmtree(tmp)
	except Failure as e:
		print(f"recolor-cursor: {e}", file=sys.stderr)
		return 1
	print(f"{count} cursors written to {target}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
