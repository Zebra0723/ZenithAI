// Runs one mission through Claude Code and reports how it went.

import { spawn } from "node:child_process";
import { claudeArgs, type MissionConfig, newStreamState, progressNote, readStreamLine } from "./missions";

export interface RunOutcome {
  ok: boolean;
  result: string;
}

export function runClaude(
  config: MissionConfig,
  folder: string,
  prompt: string,
  onProgress: (note: string) => void,
  signal?: AbortSignal,
): Promise<RunOutcome> {
  return new Promise((resolve) => {
    const env = { ...process.env };
    // An API key would win over the Max plan login. Zenith only ever uses the plan.
    delete env.ANTHROPIC_API_KEY;
    delete env.ANTHROPIC_AUTH_TOKEN;

    const child = spawn(config.claude, claudeArgs(config, prompt), { cwd: folder, env, stdio: ["ignore", "pipe", "pipe"] });
    const state = newStreamState();
    let buffer = "";
    let stderr = "";
    let lastNote = 0;
    let stoppedFor = "";

    const stop = (why: string) => {
      if (stoppedFor) return;
      stoppedFor = why;
      // SIGINT lets Claude Code end its turn cleanly; SIGKILL if it doesn't within 20s.
      child.kill("SIGINT");
      setTimeout(() => child.kill("SIGKILL"), 20_000).unref?.();
    };
    const timer = setTimeout(() => stop(`it ran past ${config.maxMinutes} minutes`), config.maxMinutes * 60_000);
    signal?.addEventListener("abort", () => stop("it was stopped"));

    child.stdout.on("data", (chunk: Buffer) => {
      buffer += chunk.toString("utf8");
      let nl: number;
      while ((nl = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line) continue;
        const before = state.latest;
        readStreamLine(state, line);
        if (state.latest !== before && Date.now() - lastNote > 60_000) {
          lastNote = Date.now();
          onProgress(progressNote(state.latest));
        }
      }
    });
    child.stderr.on("data", (chunk: Buffer) => {
      stderr = (stderr + chunk.toString("utf8")).slice(-4000);
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      resolve({ ok: false, result: `Zenith couldn't start Claude Code (${error.message}). Is it installed and logged in?` });
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (buffer.trim()) readStreamLine(state, buffer.trim());
      if (stoppedFor) {
        const sofar = state.result ?? state.latest;
        return resolve({ ok: false, result: `Zenith stopped because ${stoppedFor}.${sofar ? `\n\nWhere it got to: ${sofar}` : ""}` });
      }
      if (state.result !== null) return resolve({ ok: !state.failed, result: state.result || "Done." });
      const why = stderr.trim().split("\n").slice(-3).join(" ") || `Claude Code exited with code ${code}`;
      resolve({ ok: false, result: `The mission didn't finish: ${why}` });
    });
  });
}
