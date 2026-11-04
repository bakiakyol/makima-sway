#!/usr/bin/env python3
"""recolor-cursor: recolors an Xcursor theme to any hex color.

Usage:
	python3 design/recolor-cursor.py SOURCE_THEME TARGET_DIR "Theme Name" e22e0e

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

Uses only the Python standard library.
"""

import colorsys
import os
import shutil
import struct
import sys
from collections import Counter

IMAGE_TYPE = 0xFFFD0002   # chunk type of an "image" in the Xcursor format


def read_images(data):
	"""List the image chunks in an Xcursor file as (pixel offset, width, height)."""
	if data[:4] != b"Xcur":
		raise ValueError("not an Xcursor file")
	_, _, count = struct.unpack_from("<III", data, 4)
	images = []
	for i in range(count):
		kind, _, offset = struct.unpack_from("<III", data, 16 + i * 12)
		if kind == IMAGE_TYPE:
			# Chunk header: size, type, subtype, version, width, height, xhot, yhot, delay
			width, height = struct.unpack_from("<II", data, offset + 16)
			images.append((offset + 36, width, height))
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
		for offset, width, height in read_images(data):
			for (p,) in struct.iter_unpack("<I", data[offset:offset + width * height * 4]):
				if p >> 24 == 0xFF:
					r, g, b = (p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF
					if colorsys.rgb_to_hls(r / 255, g / 255, b / 255)[2] > 0.5:
						counter[(r, g, b)] += 1
	return counter.most_common(1)[0][0]


def main():
	if len(sys.argv) != 5:
		print(__doc__)
		return 1
	source, target, name, color = sys.argv[1:]
	source, target = os.path.expanduser(source), os.path.expanduser(target)
	tr, tg, tb = (int(color[i:i + 2], 16) / 255 for i in (0, 2, 4))
	target_h, target_l, target_s = colorsys.rgb_to_hls(tr, tg, tb)

	source_cursors = os.path.join(source, "cursors")
	target_cursors = os.path.join(target, "cursors")
	if os.path.exists(target):
		shutil.rmtree(target)
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
		for offset, width, height in read_images(data):
			n = width * height
			pixels = struct.unpack_from(f"<{n}I", data, offset)
			recolored = [recolor_pixel(p, target_h, l_ratio, s_ratio, cache) for p in pixels]
			struct.pack_into(f"<{n}I", data, offset, *recolored)
		open(dst, "wb").write(data)

	with open(os.path.join(target, "index.theme"), "w") as theme:
		theme.write(f"[Icon Theme]\nName={name}\nComment=Based on {os.path.basename(source)}, recolored to #{color}\nInherits=hicolor\n")
	print(f"{len(os.listdir(target_cursors))} cursors written to {target}")
	return 0


if __name__ == "__main__":
	sys.exit(main())
