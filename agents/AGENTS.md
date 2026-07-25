# Working agreements

Universal rules for coding agents — tool-neutral, apply in every repo.

## Writing specs and design docs

State the **destination, not the path to it**. Design docs, specs, and any written-down
decisions describe the current target state — decision-oriented, present tense.

Leave out historical/journey noise:

- No rejected-alternatives narrative ("we considered X", "A not B", "was too heavy").
- No references to the conversation/session that produced it.
- No "collapses to", "flagged pre-existing", "designed here", "turned out unnecessary".

Record a decision as a fact plus at most a one-clause reason. A future reader wants what
*is*, not how it was argued. Avoid ADRs that exist only to relitigate an alternative.

A "why" states the guarantee the design gives. Never explain a choice by describing what a
superseded design would do wrong — that is history disguised as explanation. Write
forward-only: "the passkey is a second factor that cannot be shared", not "a shared code
can't carry a second factor". Drop *instead / otherwise / in place of / not X / would
otherwise* clauses that point at the approach being replaced.

## Closing out work

Separate **resolved what surfaced** from **proven complete**. When wrapping up a pass,
state explicitly what is proven versus assumed and surface residual unknowns instead of
implying closure.

Do not offer "lock it in", "consolidate", or "merge to authoritative" as a next step until
a completeness check has actually run. Consolidating early hard-codes an incomplete model
as authoritative.

## Toolchain

Prefer when present, fall back to the classic when absent: `rg` over `grep`, `fd` over
`find`, `bat` over `cat`, `eza` over `ls`, `delta` for diffs, `z` (zoxide) over `cd`,
`htop` over `top`, `tldr` for usage. Also expected: `fzf`, `gh`, `jq`, `uv`.
