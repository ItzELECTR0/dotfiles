# Remote handover

Anything the user says that implies leaving the machine arms this: going out of town, heading out,
away for the day, travelling, leaving the desk. It is an announcement, not a question.

The arrangement is that the desktop stays powered and logged in so the self-hosted services stay
reachable, this CLI session stays alive in its terminal, and the user drives it from the Claude Code
mobile app. Problems they already know how to fix they do over SSH themselves. Anything stranger
comes here.

## When the announcement lands

Acknowledge in a couple of lines and do nothing else. No work started, no windows touched, nothing
launched.

Run one readiness check first, because a missing socket is far worse to discover from a phone:

```bash
ls "$XDG_RUNTIME_DIR"/kitty-*.sock
```

There should be two. One is the terminal this session runs in, the other is a spare kitty left idle
for exactly this purpose. Walk `$CLAUDE_PID` up its ancestry to tell them apart, as `processes.md`
describes, and name the spare's pid in the acknowledgement so it is already in the transcript when
it is needed.

Write down the layout they hand over, which workspaces are empty and which monitor this terminal
sits on, then stay idle.

## Opening a session in another project

The request sounds like "open a session in <project>". They attach to it from the mobile app
afterwards, so the job ends when the prompt is idle. Never send it work.

`cd` into the project and run `claude` in the spare window over its socket. See
`driving-the-desktop.md` for the `send-text` rules, which are easy to get wrong. Confirm it came up
by reading the foreground processes rather than the screen:

```bash
kitty @ --to unix:"$XDG_RUNTIME_DIR"/kitty-<pid>.sock ls
```

`cc` is a pwsh alias for `claude` from `profile.ps1`. Type `claude`, because `/usr/bin/cc` is the C
compiler and the alias only exists inside pwsh.

## Resuming an earlier session

`/resume` does not work in the mobile app. That is the reason this section exists. The user names a
session by what it was about, never by id, so find it first.

Transcripts live in `~/.claude/projects/<project-path>/<session-id>.jsonl`, where the path is the
absolute project path with every slash turned into a dash. Search by topic, sort by mtime, and read
the tail of the best candidate to confirm it before acting on it:

```bash
D=~/.claude/projects/-home-ELECTRO-Development-Projects-Rust-RustyPaint
grep -lie "<topic>" "$D"/*.jsonl
```

Two traps in those files. The session this CLI is running in has its own transcript with a fresh
mtime, so exclude it. And the lines carry base64 attachments and the full system prompt, so a naive
grep for a common word returns noise rather than conversation. Parse the JSON and look at
`message.content` text blocks when a match needs verifying, and quote the user's own words back when
reporting which session was picked.

Then exit whatever is running in the spare window and launch it by id:

```
claude --resume <session-id>
```

Check the running session is empty before exiting it. A session with real conversation in it is the
user's, and replacing it is their call, not yours.

## Cost

Every session opened this way bills the same weekly quota as this one. Read the limit line in the
startup banner after launching and report it, along with anything expensive the resumed session is
about to do. A full Rust gate on Opus is worth flagging before they trigger it from a phone.
