# Toolchains and project layout

## Packages

`pacman` with `paru` as the AUR helper. Beyond the Arch repos this system enables CachyOS
(`x86-64-v4` optimised builds), Chaotic-AUR, a ZFS repo, a SELinux repo, and a local file repo of
the user's own built packages living under `~/Development/Repositories`. A package can therefore
exist here and nowhere upstream.

Everything is rolling and a large share of the desktop is built from `-git` sources, so version
numbers move without warning and installed does not mean running. Never assume a version. Run
`pacman -Q <pkg>` or `<tool> --version` and read the answer. See `hyprland.md` for the commit-hash
check that catches an upgrade applied under a running session.

Do not install anything without asking first.

## Languages present

Node with npm, pnpm and bun, plus Deno. Python with pip and uv. Rust through rustup. Go, .NET, a
current OpenJDK, Dart and Flutter. GCC and Clang, with CMake, Meson, Ninja and Make. Lua and LuaJIT,
Ruby, PHP and Perl. `ccache` is wired in.

These track the bleeding edge rather than whatever is in a distro LTS, so confirm a library actually
supports the installed major version before blaming the code. Read the version, do not guess it.

## Where projects live

```
~/Development/
  Projects/{Rust,Java,Web,Unity,Mods}
  Repositories/          upstream clones and the local package repo
  Assets/
```

`~/Development` is its own ZFS dataset. Game, engine and media work also lives outside it, under
`~/Unity`, `~/Gaming` and `~/Editing`, each of which is a separate dataset too.

Several repositories already carry a root `AGENTS.md` with an indexed `.agents/` directory. Read the
root file and every relevant topic file before touching one, as `AGENTS.md` requires. A quick sweep
finds them:

```bash
find ~/Development -maxdepth 4 -name AGENTS.md
```
