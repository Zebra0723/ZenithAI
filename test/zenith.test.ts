import { expect, test } from "bun:test";
import { chmodSync, existsSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { GalaxyLink, type LinkInboxItem } from "../src/client";
import { capAnswer, claudeArgs, configFromEnv, missionFolder, missionPrompt, slug } from "../src/missions";
import { Practice } from "../src/practice";
import { runClaude, runPractice } from "../src/runner";
import { POWERS } from "../src/zenith";

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

// Galaxy Trainer practice drills.

/** A stand-in Galaxy Link hub that records what Zenith sends it. */
function fakeHub() {
  const received: { method: string; path: string; body: any }[] = [];
  const server = Bun.serve({
    port: 0,
    async fetch(req) {
      const url = new URL(req.url);
      const body = req.method === "GET" ? null : await req.json().catch(() => null);
      received.push({ method: req.method, path: url.pathname, body });
      if (url.pathname === "/v1/context") return Response.json({ text: "The user likes short plans." });
      return Response.json({ ok: true });
    },
  });
  const link = new GalaxyLink("zenith", { port: server.port, token: "t", powers: POWERS, name: "Zenith" });
  return { server, link, received };
}

/** A fake claude that records its args (NUL-separated), cwd and how full the cwd was. */
function fakeClaude(name: string, body: string) {
  const path = join(dir, name);
  const log = join(dir, `${name}.args`);
  writeFileSync(path, `#!/bin/bash
printf '%s\\0' "$@" > "${log}"
echo "$PWD" > "${log}.cwd"
ls -A | wc -l | tr -d ' ' > "${log}.files"
${body}
`);
  chmodSync(path, 0o755);
  return {
    path,
    ran: () => existsSync(log),
    args: () => readFileSync(log, "utf8").split("\0").slice(0, -1),
    cwd: () => readFileSync(`${log}.cwd`, "utf8").trim(),
    files: () => Number(readFileSync(`${log}.files`, "utf8").trim()),
  };
}

const drill: LinkInboxItem = { id: 1, kind: "practice", taskId: "p_ab12", text: "Build the tennis team a website.\nPlayers: 12", replyTo: "" };

test("Zenith tells Link it can practice", async () => {
  expect(POWERS).toEqual(["missions", "practice"]);
  const { server, link, received } = fakeHub();
  await link.hello();
  server.stop(true);
  expect(received.find((r) => r.path === "/v1/hello")?.body.powers).toContain("practice");
});

test("a drill is planned as a strict dry run and answered through the practice endpoint", async () => {
  const claude = fakeClaude("plan", `
echo '{"type":"assistant","message":{"content":[{"type":"text","text":"Plan follows."}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"1. First steps: sketch pages. 2. Checking: open it."}'`);
  const { server, link, received } = fakeHub();
  const config = { ...configFromEnv({ ZENITH_MISSIONS: dir, ZENITH_MODEL: "opus" }), claude: claude.path };
  const sent = await new Practice(link, config).handle(drill);
  server.stop(true);

  expect(sent).toBe(true);
  const answer = received.find((r) => r.path === "/v1/practice/p_ab12/answer");
  expect(answer?.method).toBe("POST");
  expect(answer?.body).toEqual({ answer: "1. First steps: sketch pages. 2. Checking: open it." });

  const args = claude.args();
  expect(args[args.indexOf("--max-turns") + 1]).toBe("1");
  expect(args[args.indexOf("--model") + 1]).toBe("opus");
  const denied = args[args.indexOf("--disallowedTools") + 1].split(",");
  for (const tool of ["Bash", "Edit", "Write", "MultiEdit", "NotebookEdit", "WebFetch", "WebSearch", "Task", "Read", "Glob", "Grep", "TodoWrite"]) {
    expect(denied).toContain(tool);
  }
  for (const flag of ["--allowedTools", "--allowed-tools", "--permission-mode", "--dangerously-skip-permissions", "--add-dir", "--mcp-config"]) {
    expect(args).not.toContain(flag);
  }
  expect(JSON.parse(args[args.indexOf("--settings") + 1]).sandbox).toMatchObject({ enabled: true, allowUnsandboxedCommands: false });
  const prompt = args[args.indexOf("-p") + 1];
  expect(prompt).toContain("Build the tennis team a website.");
  expect(prompt).toContain("The user likes short plans.");
  expect(prompt).toContain("DRY RUN");
  // A fresh, empty folder that's gone afterwards.
  expect(claude.files()).toBe(0);
  expect(claude.cwd()).toContain("zenith-practice-");
  expect(existsSync(claude.cwd())).toBe(false);
});

test("drills are skipped while a mission runs, and dropped when one starts", async () => {
  const quick = fakeClaude("quick", `echo '{"type":"result","subtype":"success","result":"plan"}'`);
  const { server, link, received } = fakeHub();
  const practice = new Practice(link, { ...configFromEnv({ ZENITH_MISSIONS: dir }), claude: quick.path });

  practice.missionStarted();
  expect(await practice.handle(drill)).toBe(false);
  expect(quick.ran()).toBe(false);
  practice.missionEnded();

  const slow = fakeClaude("slowplan", "exec sleep 30");
  const busy = new Practice(link, { ...configFromEnv({ ZENITH_MISSIONS: dir }), claude: slow.path });
  const started = Date.now();
  const pending = busy.handle(drill);
  await Bun.sleep(300);
  expect(await busy.handle({ ...drill, taskId: "p_two" })).toBe(false); // one drill at a time
  busy.missionStarted();
  expect(await pending).toBe(false);
  expect(Date.now() - started).toBeLessThan(5000);
  server.stop(true);
  expect(received.some((r) => r.path.startsWith("/v1/practice/"))).toBe(false);
});

test("a dry run that runs too long gives no answer", async () => {
  const slow = fakeClaude("slowdry", "exec sleep 30");
  const out = await runPractice({ ...configFromEnv({}), claude: slow.path }, "go", { timeoutMs: 200 });
  expect(out).toBeNull();
  expect(capAnswer("x".repeat(3000)).length).toBeLessThanOrEqual(1500);
});
