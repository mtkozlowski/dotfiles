# carapace completions, initialised from a cached init script so that nothing
# on the login path can stall. `source <(carapace _carapace)` runs the binary
# inside process substitution, and the shell blocks on that pipe with no
# timeout — on a machine deep in swap the prompt never arrives and the box
# becomes impossible to log into. Sourcing a plain file cannot stall.
#
# The cache is rebuilt detached, so no shell ever waits on carapace: a shell
# that finds a cold cache goes without carapace completions and the next one
# picks them up. That costs one shell after a fresh install or a carapace
# upgrade. No-ops on machines without carapace.
#
# Must be sourced after compinit (carapace registers completions via compdef)
# and before the syntax-highlighting plugin, which has to load last.

export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense' # optional
typeset -g CARAPACE_INIT="${XDG_CACHE_HOME:-$HOME/.cache}/carapace/init.zsh"

# Force a synchronous rebuild. Use after changing $CARAPACE_BRIDGES, which is
# read when the init script is generated.
carapace-refresh() {
  [[ -d "${CARAPACE_INIT:h}" ]] || mkdir -p "${CARAPACE_INIT:h}"
  if carapace _carapace > "$CARAPACE_INIT.$$"; then
    mv -f "$CARAPACE_INIT.$$" "$CARAPACE_INIT"
    source "$CARAPACE_INIT"
  else
    rm -f "$CARAPACE_INIT.$$"
    print -u2 "carapace-refresh: generation failed, kept existing cache"
    return 1
  fi
}

if (( $+commands[carapace] )); then
  [[ -d "${CARAPACE_INIT:h}" ]] || mkdir -p "${CARAPACE_INIT:h}"

  # Rebuild when the cache is missing, empty, or older than the binary.
  if [[ ! -s "$CARAPACE_INIT" || "$commands[carapace]" -nt "$CARAPACE_INIT" ]]; then
    # Reap temp files abandoned by a rebuild that never finished, so a machine
    # that stalls carapace on every login does not collect one 0-byte file per
    # shell. Only the rare rebuild path pays for this. `find` rather than a
    # glob qualifier: no dependency on extendedglob or bareglobqual being set,
    # and it stays quiet when nothing matches.
    find "${CARAPACE_INIT:h}" -maxdepth 1 -name "${CARAPACE_INIT:t}.[0-9]*" \
      -mmin +60 -delete 2>/dev/null

    # Cap the rebuild so a stalled carapace exits instead of living on as a
    # disowned process for every shell started. GNU coreutils ships `timeout`;
    # on a machine without it the rebuild is simply unbounded.
    local -a _carapace_gen=(carapace _carapace)
    if (( $+commands[timeout] )); then
      _carapace_gen=(timeout 20 $_carapace_gen)
    elif (( $+commands[gtimeout] )); then
      _carapace_gen=(gtimeout 20 $_carapace_gen)
    fi

    # `&!` = background and disown: the shell will not wait or report on it.
    # Temp name carries $$ so concurrent shells cannot clobber each other, and
    # the mv is atomic so no shell ever sources a half-written file.
    { $_carapace_gen > "$CARAPACE_INIT.$$" 2>/dev/null \
      && mv -f "$CARAPACE_INIT.$$" "$CARAPACE_INIT" \
      || rm -f "$CARAPACE_INIT.$$" } &!
    unset _carapace_gen
  fi

  [[ -s "$CARAPACE_INIT" ]] && source "$CARAPACE_INIT"
fi
