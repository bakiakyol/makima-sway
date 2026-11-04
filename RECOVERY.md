# What to do if Sway won't start

Keep a copy of this somewhere else too (on your phone, on paper). If the screen goes black, you may not be able to read this file.

## 1. Switch to another TTY

Press `Ctrl+Alt+F3` and log in with your username and password. That TTY is a plain shell that this setup doesn't touch.

(If Sway is frozen and `Ctrl+Alt+F3` doesn't respond, wait a few seconds and try again. As a last resort, briefly press the power button.)

## 2. Stop Sway from starting automatically

```bash
nano ~/.bash_profile
```

Put a `#` at the start of the line with `exec sway`, then save (`Ctrl+O`, `Enter`, `Ctrl+X`).

## 3. Find the cause

Log in on the Sway TTY and start Sway by hand with a debug log:

```bash
sway -d 2> ~/sway.log
```

If it doesn't come up, switch back with `Ctrl+Alt+F3` and look at the log:

```bash
grep -i -E "error|fail" ~/sway.log | head -30
```

## 4. Known problems and what to try first

| Symptom | Try |
|---|---|
| Black screen, or "atomic" / "modeset" errors | `WLR_DRM_NO_ATOMIC=1 sway` (relevant with kernel options like `amdgpu.dc=0`) |
| Broken picture, strange colors, rendering glitches | `WLR_RENDERER=pixman sway` (software rendering: slow, but it works) |
| Config error (yellow/red bar at the top) | `sway --validate` shows the bad line |
| Wrong keyboard layout | check `input type:keyboard { xkb_layout ... }` in `~/.config/sway/config` |
| Bar, terminal, or lock screen look like defaults | the `~/.config/makima-sway` link is broken; run `./install.sh` again from the repo |

## 5. Another desktop on the same account (i3 in my case)

This setup doesn't change i3's config. Shared scripts check `$WAYLAND_DISPLAY`, so they work on both.
Don't run i3 and Sway at the same time: the D-Bus session is per user, so notifications and new Firefox windows can end up on the wrong screen. Log out of one before starting the other.
