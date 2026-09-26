# Global working rules

These rules apply to every project. More specific project instructions add context and take
precedence where they explicitly conflict.

## This machine

Notes describing this specific system live in `~/.agents/`. They are facts about the environment
rather than rules. The one-topic-per-file and index rules under `Repository agent documentation`
apply to them.

Read `~/.agents/machine.md` for the storage model, privileges, SELinux, locale, and the directories
that are off limits.

Read `~/.agents/shell-and-dotfiles.md` before touching shell configuration, the stow symlinks under
`~/.config`, or git settings.

Read `~/.agents/hyprland.md` before reading or writing anything under `~/.config/hypr`, and before
using `hyprctl`.

Read `~/.agents/driving-the-desktop.md` before sending input, controlling windows, capturing the
screen, notifying the user, or doing anything that needs a GUI. The desktop is do-not-disturb by
default.

Read `~/.agents/processes.md` before killing anything or starting long-running work.

Read `~/.agents/toolchains.md` for package management, installed language tooling, and where
projects live.

Read `~/.agents/remote-handover.md` when the user says anything implying they are leaving the
machine, or asks for a session opened or resumed in the spare terminal for use from the mobile app.

## Work toward the outcome

The user usually describes the outcome, not every contingency. Optimize for the best result, not
literal compliance with a possibly incomplete implementation idea.

- Take small, reversible initiative for obvious edge cases and integration points that serve the
  same goal.
- If a better result requires a meaningfully different architecture, UX, scope, or omission of
  something explicitly requested, stop and ask first.
- Judge this by intent and blast radius. Do not turn a narrow request into adjacent cleanup.

## Inspect before acting

- Read the repository's root agent instructions before touching anything, then read every indexed
  topic file relevant to the system being changed.
- Never guess a toolchain, runtime, dependency, or framework version. Read the project's source of
  truth and use APIs compatible with it.
- Prefer current, non-deprecated APIs within the project's actual version constraints. Flag a
  deprecated existing pattern instead of copying it into new work.
- Use the repository's documented build and test entry points. Never claim a check passed if it was
  not run. Hand off any user-only verification with exact steps.

## Repository agent documentation

For project-specific agent documentation, keep `AGENTS.md` at the repository root as the canonical
index and put detailed guidance in `.agents/`.

- The root file contains only the project shape, working philosophy, always-relevant rules, and one
  line per `.agents/` file saying when to read it.
- Keep one topic per `.agents/` file and name the file after the topic. Put new detail in an existing
  topic when it fits. If a new topic is needed, create the file and add it to the root index.
- A topic file without an index entry is undiscoverable and therefore incomplete.
- Keep the root file small. System-specific detail, rationale, exact paths, constraints, and worked
  examples belong in the relevant topic file.
- Make `AGENTS.md` canonical. Where another agent requires a different filename, use a supported
  import or symlink instead of maintaining a second copy. Edit the canonical file, not its adapter.
- The global notes are the one exception to that placement. There, `AGENTS.md` sits inside
  `~/.agents/` next to its topic files. Per project it stays at the repository root,
  where an agent finds it immediately instead of having to open a hidden directory first.
- Write down the reasoning that future maintainers need. Keep exact facts such as names, paths,
  numbers, and constraints, but cut restatement and ceremony.
- Documentation describes the project as it is now. Rewrite or delete stale material when the code
  changes. Git history is the history.
- One fact has one owner. Cross-link to it rather than duplicating it.

If a repository has `ROADMAP.md`, it holds unfinished intent, not implementation history. Completing
work means removing what is done and leaving only what remains genuinely open. Delete empty sections
and stale claims. Do not add dated "Implemented" write-ups.

## Code comments

Comments are minimal by design. Prefer readable code over comments that explain unreadable code.

- If code is understandable at face value, add no comment.
- If it is slightly ambiguous, use at most one line above the relevant declaration or block.
- If it is genuinely complex, use at most two lines. Two lines is a hard ceiling for every comment
  you add, including type, function, and inline comments.
- Do not add documentation blocks, generated summaries, file banners, author/date blocks, divider
  comments, or comments that merely label a section.
- Inline comments are rare and explain one specific hard part that cannot be made clear in code.
- Long-form rationale belongs in the relevant `.agents/` topic file.

## Human-facing writing

A README is for developers and people trying the project. It is not an agent file or a design
document. Say what the project does and how to use it.

- Cut design rationale, rejected alternatives, internal type and method names, and low-level
  walkthroughs from user-facing documentation. Put durable technical reasoning in `.agents/`.
- Be much shorter than feels natural. One clear sentence beats a paragraph that restates it.
- Write casually and in first person. Avoid formal, corporate, or specification-style prose. Humour
  is welcome when it fits.
- Use ordinary ASCII punctuation. Do not write em dashes, right-pointing double angle marks, middle
  dots, or decorative typographic punctuation. Use commas, full stops, colons, parentheses, or
  separate sentences.
- Never document the same thing in two repositories. Link to the canonical published documentation.
- Do not write documentation as if every reader has the maintainer's local checkout. Avoid sibling
  repository paths and commands that depend on a private directory layout.
- A useful README order is one line saying what it is and what it targets, licence, optional lore or
  background, then usage. Use question-style table headers such as `What?`. Give prerequisites,
  build, and test commands in separate fenced blocks.

Apply the same style to release notes, issue comments, and pull request descriptions. Code comments
follow the stricter comment rules above.

## State, configuration, and compatibility

- Keep one source of truth. Derive values from authoritative state when storing another copy could
  go stale.
- Place data and rules according to what they are true of and who owns them, not whichever consumer
  happens to need them today.
- Do not silently overwrite hand-authored or user-authored configuration, tuning, or content. Make
  migrations explicit and preserve existing values unless the task specifically authorizes a reset.
- Versioning is the maintainer's decision, not an automatic side effect of a change. Never change a
  shipped version number unless asked. Report compatibility, schema, protocol, or migration impact
  and let the maintainer decide the version change.

## Commit messages

Commit messages are simple and to the point.

- The subject says what changed in one short line. Prefer the outcome over the procedure.
- Omit the body by default. Add a short body only when the subject would hide an essential
  compatibility, migration, or user-visible consequence.
- Do not narrate the diff, list files or symbols, repeat the issue, or explain the implementation.
- The implementation should be clear from readable code. A genuinely non-obvious local detail gets
  a comment under the two-line ceiling. Durable system reasoning belongs in `.agents/`, not a commit
  essay.
- Never add a `Co-Authored-By` or equivalent co-author trailer unless the user explicitly requests
  it for that commit.
- Never include a session ID in a commit message. There are no exceptions.

## Git authority

- Never create a commit without explicit permission for the current work.
- Never push. Pushing is always the user's action.
