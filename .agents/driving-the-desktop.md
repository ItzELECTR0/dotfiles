# Driving the desktop

How to observe and act on the running session without hijacking it. Read `hyprland.md` first for the
Lua dispatch syntax and the permission model.

## Rule zero

This is the user's live daily-driver session, not a test harness. Never take focus, never move or
resize a window they are using, never capture the screen for your own exploration, and never restart
the compositor or the shell. Prefer a call that reports something over a call that changes something.

## Sending keys

This works without any extra package, because it happens inside the compositor rather than through an
input device:

```bash
hyprctl dispatch 'hl.dsp.send_shortcut({mods="CTRL", key="S", window="class:someapp"})'
hyprctl dispatch 'hl.dsp.send_key_state({mods="", key="F13", state="down", window="class:someapp"})'
```

`window` targets a specific client, so the keystroke does not depend on what is focused and does not
need focus stolen to land. Always pass it.

Delivery is confirmed. A probe window was launched, focus was deliberately moved away from it, and a
`send_shortcut` aimed at it by title still landed in it. So the targeting is real and focus-
independent, and this is the keyboard path to use on this system. `ydotool key` is not.

Limits worth knowing before planning around this:

- One dispatch per key. There is no "type this string" dispatcher, so text entry is a loop and is
  slow and visibly stuttery for anything longer than a short field.
- `send_key_state` needs a matching `up` for every `down`, and a missed `up` leaves a modifier stuck
  in that client.
- Key names are xkb keysyms, the same vocabulary `hl.bind` uses in `input/keybinds.lua`.

## Moving the pointer, and clicking

`hl.dsp.cursor.move` and `hl.dsp.cursor.move_to_corner` move the pointer. There is no mouse button
dispatcher anywhere in `hl.dsp`, so the compositor itself cannot synthesise a click or a scroll.

`ydotool` fills that gap. Its user unit is `ydotool.service`, note the name, there is no trailing `d`
even though it runs `ydotoold`. `/dev/uinput` carries an ACL for the user, so nothing runs as root,
and its socket under `$XDG_RUNTIME_DIR` is mode `0600`.

```bash
ydotool mousemove -x 2 -y 0        # relative, verified
ydotool click 0xC3                 # 0x40 down + 0x80 up, 0x03 side button
```

Pointer motion is scaled by the user's negative input sensitivity, so a request for 2 pixels can land
as 1. Read `hyprctl cursorpos` before and after rather than assuming the delta.

## ydotool keyboard, and the permission that gates it

`ydotool` drives the keyboard fully, including bulk text. Verified end to end into a real focused
window: a three-key sequence and a thirty-character `ydotool type` both arrived intact, no dropped
characters.

```bash
ydotool key --key-delay 30 30:1 30:0      # evdev keycodes, :1 down :0 up
ydotool type "some text"                  # bulk text, one invocation
```

It only works because `variables/permissions.lua` carries an allow for the device name, ahead of the
catch-all keyboard deny:

```lua
hl.permission({ binary = "ydotoold[- ]virtual[- ]device", type = "keyboard", mode = "allow" })
```

Without that rule the deny swallows every key while the pointer keeps working, because the pointer is
not gated by the keyboard permission. If keys ever stop arriving, check that rule first, and remember
it only takes effect after a full compositor restart.

## Which keyboard path to use

Both work, and they are good at different things.

| | `send_shortcut` | `ydotool` |
| --- | --- | --- |
| Targets a window by name | yes, focus untouched | no, goes to whatever is focused |
| Bulk text | one dispatch per key | `ydotool type`, one invocation |
| Clicks and scroll | not possible | yes |

Default to `send_shortcut` for keys, because not stealing focus is worth a lot on a live session.
Reach for `ydotool` when you need a lot of text, or a click.

## The lesson that cost the most time here

Every early conclusion about this was wrong because permissions do not hot-reload. Each test used
`hyprctl reload`, so the boot-time deny stayed in force throughout, including during a control that
supposedly disabled it. That produced a confident and completely false "the permission system is
ruled out".

Never conclude anything about a permission from a reload-only experiment. See the permissions section
of `hyprland.md`.

A second, independent error compounded it: `hl.bind("code:N")` takes the **xkb** keycode, which is
the evdev code plus 8. Sending evdev 183 and binding `code:183` can never match; the bind has to be
`code:191`. Keysym binds such as `Scroll_Lock` are easier to get right.

Never diagnose input by subscribing to `input.keyboard.key`. That event carries no device field, so a
subscription captures whatever the user is typing on their real keyboard. Bind the specific key you
are sending, or use a probe window as described below.

`xdotool` is installed and `DISPLAY` is served by `xwayland-satellite`, so it can drive XWayland
clients only. Native Wayland windows are invisible to it, which covers most of what is running.

## Window and workspace control

`hl.dsp.window.*` and `hl.dsp.workspace.*` cover close, kill, move, resize, float, fullscreen, pin,
tag, group and workspace operations. Query first with `hl.get_windows({ class = "..." })` so you act
on one address rather than a match that could sweep up something else.

To start a GUI without yanking the user out of what they are doing, launch it through
`hl.dsp.exec_cmd` and give it a rule with `no_initial_focus` or a `"N silent"` workspace, the same
pattern `display/rules.lua` already uses.

## Telling the user something

```bash
# compositor overlay, icon -1 is none
hyprctl notify <icon> <timeout_ms> "<colour>" "<text>"
# their real notification stack
noctalia msg notification-show "<title>" "<body>"
```

Check `noctalia msg notification-dnd-status` before sending anything non-urgent. `noctalia msg` has
about a hundred subcommands covering volume, brightness, wallpaper, bars, dock, clipboard,
screenshots, night light, wifi, bluetooth and panels, so prefer it over poking those subsystems
directly.

## Screenshots and recording

The capture tools are installed and already hold screencopy permission, so they capture with no
prompt. See `variables/permissions.lua` for which binaries are granted.

Permission granted is not permission earned. Capture only when the user asks for a screenshot, keep
it in the session scratchpad, and delete it when done.

## Kitty remote control

`kitty.conf` sets `allow_remote_control socket-only` with
`listen_on unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}.sock`. `socket-only` accepts control over the
socket and refuses it over the TTY, so terminal output can never drive kitty, and the socket lives in
a user-only directory rather than an abstract address any process could reach.

Neither option can be applied by a config reload, so only kitty instances started after the change
carry a socket. Find one and use it:

```bash
ls "$XDG_RUNTIME_DIR"/kitty-*.sock
kitty @ --to unix:"$XDG_RUNTIME_DIR"/kitty-<pid>.sock ls
```

This is how to run something in a terminal the user can watch, rather than blind in a tool call.
Remember that `kitty @ ls` reports window titles and working directories, and `get-text` reads
scrollback, so scope the query and do not dump the lot.

## Testing input safely, with a probe window

Never test input against the user's own windows. Launch a throwaway one through kitty remote control,
have it record what it receives, and close it:

```bash
SOCK=$(ls "$XDG_RUNTIME_DIR"/kitty-*.sock | head -1)
ORIG=$(hyprctl activewindow -j | jq -r .address)
kitty @ --to "unix:$SOCK" launch --type=os-window --os-window-class kitty-floating \
  --title AGENTPROBE bash -c "IFS= read -rsn1 -t 25 k; printf 'GOT:[%s]' \"\$k\" > /tmp/probe.txt"
# ... send the key, read /tmp/probe.txt ...
hyprctl dispatch "hl.dsp.focus({window=\"address:$ORIG\"})"
kitty @ --to "unix:$SOCK" close-window --match title:AGENTPROBE
```

`--os-window-class kitty-floating` picks up the existing float rule so the probe does not re-tile the
user's layout. Record the active window address first and restore focus at the end, from a trap so it
happens even on failure.

`--keep-focus` does not hold for `--type=os-window`: the probe takes focus anyway. Anything needing
the probe unfocused has to move focus back explicitly after it opens. Say so before running this,
because it does briefly disturb the session.

## Clipboard

`wl-copy` and `wl-paste` are present, a clipboard persister keeps content alive after a client exits,
and a clipboard history tool is installed. Reading the clipboard reads whatever the user last copied,
which may be a password: do not read it unprompted.
