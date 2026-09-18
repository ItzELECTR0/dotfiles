# Machine

Arch Linux, rolling, running a CachyOS kernel. systemd as init, SDDM as the display manager. The
exact kernel, CPU, GPU and memory are one command away (`uname -r`, `lscpu`, `nvidia-smi`, `free -h`)
and go stale fast, so read them rather than trusting anything written here.

What actually changes how you work:

## NVIDIA on Wayland

The GPU is NVIDIA on the proprietary driver, and the session is configured around it:
`GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `LIBVA_DRIVER_NAME=nvidia`,
`NVD_BACKEND=direct`. Assume NVIDIA-specific quirks apply to anything graphical, and do not suggest
a fix that silently assumes Mesa.

## Storage is ZFS, and the home directories are separate datasets

`/` and `/home` are on ZFS, on top of LUKS. Several directories under `~` are their own datasets
rather than plain folders, so `mv` between them is a full copy, not a rename. Budget time and space
accordingly on anything large.

Pools here run close to full. Check `zpool list` and `zfs list` before writing a large artefact, and
put intermediates in the session scratchpad instead.

## Directories that are off limits

`~/Vault`, `~/Desktop`, `~/Downloads`. Several other home entries are symlinks into `~/Vault` and
inherit the same rule, including `Documents` and `Pictures`. Resolve symlinks before reading anything
under `~`, because the path you were given may not be where the file lives.

## Privileges

Several escalation paths are installed. Never escalate on your own initiative: ask, and hand over the
exact command for the user to run. `id` will tell you what the account can actually do if you need to
know.

SELinux is enabled and currently permissive, but the config file selects enforcing, so a reboot can
start denying what works today. If something fails only as a privileged or containerised operation,
check `journalctl -t audit` before blaming the code.

## Locale and time

`LANG=en_GB.UTF-8` with `LC_COLLATE=C`, and the timezone is European. `BLOCK_SIZE=si` is exported and
`ls`, `df` and `du` are aliased to `--si`, so sizes in the user's terminal are powers of 10, not
powers of 2. Write dates in ISO form.

## This box is not a test rig

It runs long-lived services that other machines and people depend on, a libvirt stack with GPU
passthrough, and a container runtime. Enumerate with `systemctl list-units --state=running` before
assuming anything is disposable, and see `processes.md` before stopping or killing any of it.
