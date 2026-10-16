---
name: project-mv
description: Move or rename a project directory together with its agent history (Claude Code transcripts and memory, Codex, opencode, Paseo, git worktrees). Use when the user asks to move, rename or relocate a project or repo folder, or reports lost sessions after moving one.
---

`project-mv OLD NEW` (on PATH from `~/.config/scripts`) does the whole move. `project-mv --help` lists every store it rewrites, the flags, and the exit codes. Run it. Never move agent data by hand.

1. **Check where you stand.** The tool refuses to start while a claude, codex or opencode process works inside OLD. Your own session counts when your working directory is inside OLD. In that case, give the user the exact command and stop. They run it after quitting the sessions in that project.
2. **Rename memory content first** when the project's name changes. Edit the memory files under `~/.claude/projects/<encoded OLD>/memory/`: file names, `name:` slugs, `MEMORY.md` pointers, and in-body mentions of the old name. The tool rewrites paths only. Names in prose stay as they are.
3. **Dry run.** Run `project-mv -n OLD NEW` and show the user the plan. NEW is the full destination path. Add `-p` when its parent does not exist yet.
4. **Run** `project-mv -y OLD NEW` once the user approves the plan.
5. **Finish skipped steps.** Exit status 3 means a step was skipped. This always happens to `~/.claude.json` while any Claude Code process runs, and that includes you. Tell the user to quit every Claude Code session (and Paseo, if it was named) and then run the same command again. Running it again is safe and completes the move.
6. **Close out.** The run ends with a list of files that still mention OLD. Report each one. Shell config and dotfiles entries (`~/.zshrc`, gh-dash `repoPaths`, scripts) are the user's to change, so propose the edit. Done means the list is empty or every remaining entry is reported to the user.
