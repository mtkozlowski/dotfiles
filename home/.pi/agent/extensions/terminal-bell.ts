// Ring the terminal bell whenever pi hands control back to me, so a pi pane
// raises the same tmux window alert a Claude Code pane does. tmux turns the BEL
// byte into the alert (`monitor-bell on`, `bell-action any` in tmux.conf), and
// Claude Code gets there through `preferredNotifChannel: terminal_bell`.
//
// Pi has no such setting, so this extension writes the byte itself, on the two
// moments pi stops and waits: the agent settling after a run, and an extension
// opening a blocking dialog.

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const BEL = "\x07";

function ring(): void {
  if (!process.stdout.isTTY) {
    return;
  }
  try {
    process.stdout.write(BEL);
  } catch {
    // A closed or full stdout is not worth failing the turn over.
  }
}

export default function (pi: ExtensionAPI) {
  // TUI only. Print, JSON and RPC modes have no window for tmux to flag, and
  // subagent sessions run in a mode other than "tui".
  let inTui = false;
  let ranSinceLastBell = false;

  pi.on("session_start", (_event, ctx) => {
    inTui = ctx.mode === "tui";
  });

  pi.on("agent_start", () => {
    ranSinceLastBell = true;
  });

  pi.on("agent_settled", (_event, ctx) => {
    // isIdle() is false when another extension has already started a new run,
    // in which case pi is still busy and the wait is not mine.
    if (!inTui || !ranSinceLastBell || ctx.isIdle?.() !== true) {
      return;
    }
    ranSinceLastBell = false;
    ring();
  });

  pi.on("ui_prompt_start", () => {
    if (inTui) {
      ring();
    }
  });
}
