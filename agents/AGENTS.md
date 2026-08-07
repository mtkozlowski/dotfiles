# Working agreements

Universal rules for coding agents — tool-neutral, apply in every repo.

## Plain language

Applies to every word written for a human reader: chat replies, specs, design docs, tickets,
issues, PR bodies, review reports, commit bodies, and code comments. Code, identifiers, quoted
output, and file paths are exempt.

- Use short common words. Write full sentences with articles.
- One idea per sentence. No em-dash asides.
- Spell operators out as words: "is", "becomes", "1 through 10". No `=`, `→`, `..`, `~` in prose.
- Name a thing the same plain way every time. Do not coin a shorthand noun and then reuse it as
  if it were shared vocabulary.
- Avoid the "X, not Y" contrast, three-item lists written for rhythm, and a closing one-liner.
- Say it plainly. No metaphors.
- No emoji. Use a table only for a real matrix.

In chat, also:

- Lead with the answer or the blocker. Add context only if it changes what I do.
- Say "I don't know" or "I didn't check" in those words.
- Skip preamble, recap, and offers of further help.

The sections below set what a document must contain. This section sets how it reads.

## Writing specs and design docs

State the **destination, not the path to it**. Design docs, specs, and any written-down
decisions describe the current target state — decision-oriented, present tense.

Leave out historical/journey noise:

- No rejected-alternatives narrative ("we considered X", "A not B", "was too heavy").
- No references to the conversation/session that produced it.
- No "collapses to", "flagged pre-existing", "designed here", "turned out unnecessary".

Record a decision as a fact plus at most a one-clause reason. A future reader wants what
_is_, not how it was argued. Avoid ADRs that exist only to relitigate an alternative.

A "why" states the guarantee the design gives. Never explain a choice by describing what a
superseded design would do wrong — that is history disguised as explanation. Write
forward-only: "the passkey is a second factor that cannot be shared", not "a shared code
can't carry a second factor". Drop _instead / otherwise / in place of / not X / would
otherwise_ clauses that point at the approach being replaced.

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
