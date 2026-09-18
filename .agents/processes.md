# Processes

## The session you are running inside

```
display manager -> Hyprland -> terminal -> pwsh -> claude -> bash (tool calls)
```

Every one of those is an ancestor. Killing the terminal, the shell, the CLI or the compositor kills
the agent session, and killing the compositor takes the user's whole desktop with it. `$CLAUDE_PID`
holds the CLI pid.

## What is and is not guarded

`pkill` is wrapped by a shell function from the Claude Code snapshot: it runs the same pattern
through `pgrep` first and refuses if the match includes `$CLAUDE_PID`. That guard is why
`pkill -f claude` no longer detonates the session.

Nothing else is guarded. `killall`, `kill` against a pid you resolved yourself,
`pgrep -f ... | xargs kill`, `systemctl --user stop`, and anything run under a privilege escalation
all bypass it completely.

## How to kill something safely

1. `pgrep -a <pattern>` and read the result before killing anything.
2. Prefer exact matching: `pkill -x <name>`, or a pid you confirmed in step 1.
3. For processes you started, `pkill -P $$` scopes to your own children.
4. Default to `SIGTERM`. Use `-9` only after a term has visibly failed.
5. Never use a bare generic pattern such as `node`, `python`, `bash` or `electron`. All of those
   match many of the user's real processes.

Some of the user's own keybinds and scripts do use `killall -9` on desktop components. That is
theirs. Do not reach for it.

## Do not disturb

This machine runs long-lived user and system services that hold real state, including networking,
file sharing, sync, virtualisation and media daemons, plus desktop apps launched at login. Enumerate
before touching anything:

```bash
systemctl --user list-units --type=service --state=running
systemctl list-units --type=service --state=running
```

## Long-running work

Use the harness background mechanism rather than `&` or `nohup`, so the job is tracked and its exit
is reported. Foreground `sleep` is blocked. Builds here are heavy and `ccache` is enabled, so do not
fan out parallel compiles without saying so first.

## Containers

There is no Docker daemon. `podman` is installed rootless and `DOCKER_HOST` points at the podman
socket under `$XDG_RUNTIME_DIR`, so tools that speak the Docker API work, but the `docker` binary
does not exist. Write `podman`.
