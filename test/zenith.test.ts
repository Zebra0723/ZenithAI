import { expect, test } from "bun:test";
import { chmodSync, existsSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { claudeArgs, configFromEnv, missionFolder, missionPrompt, slug } from "../src/missions";
import { runClaude } from "../src/runner";

const dir = mkdtempSync(join(tmpdir(), "zenith-"));

test("missions get tidy folders", () => {
  expect(slug("Build a website for the tennis team!")).toBe("build-a-website-for-the-tennis-team");
  const folder = missionFolder(dir, "Plan a trip", new Date("2026-10-28T12:00:00Z"));
  expect(folder).toEndWith("2026-10-28 plan-a-trip");
  expect(existsSync(folder)).toBe(true);
});

test("Claude Code runs sandboxed, with nobody to ask", () => {
  const args = claudeArgs(configFromEnv({ ZENITH_MISSIONS: dir }), "go");
  const settings = JSON.parse(args[args.indexOf("--settings") + 1]);
  expect(settings.sandbox).toMatchObject({ enabled: true, allowUnsandboxedCommands: false, failIfUnavailable: true });
  expect(settings.sandbox.filesystem.denyRead).toEqual(["~/"]);
  expect(args).toContain("--permission-prompts");
  expect(args[args.indexOf("--permission-mode") + 1]).toBe("acceptEdits");
  expect(missionPrompt({ id: "t", from: "comet", title: "T", instructions: "Do it" }, "/m", "Likes blue")).toContain("Likes blue");
});

test("a run reports its final answer, and never uses an API key", async () => {
  const fake = join(dir, "claude");
  writeFileSync(fake, `#!/bin/bash
[ -n "$ANTHROPIC_API_KEY" ] && { echo '{"type":"result","is_error":true,"result":"used a key"}'; exit 0; }
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Building it now. More soon."}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"Built it: index.html"}'
`);
  chmodSync(fake, 0o755);
  process.env.ANTHROPIC_API_KEY = "sk-nope";
  const out = await runClaude({ ...configFromEnv({ ZENITH_MISSIONS: dir }), claude: fake }, dir, "go", () => {});
  expect(out).toEqual({ ok: true, result: "Built it: index.html" });
});

test("a run that won't stop is stopped at its time limit", async () => {
  const slow = join(dir, "slow");
  writeFileSync(slow, "#!/bin/bash\nexec sleep 30\n");
  chmodSync(slow, 0o755);
  const out = await runClaude({ ...configFromEnv({}), claude: slow, maxMinutes: 0.01 }, dir, "go", () => {});
  expect(out.ok).toBe(false);
  expect(out.result).toContain("ran past");
});
