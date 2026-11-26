import { describe, expect, test } from "bun:test";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";

const WORKFLOW = join(import.meta.dir, "../../.github/workflows/release.yml");

type Step = {
  name?: string;
  uses?: string;
  run?: string;
  with?: Record<string, unknown>;
  "working-directory"?: string;
};

type Job = {
  uses?: string;
  needs?: string | string[];
  permissions?: Record<string, string>;
  defaults?: { run?: { "working-directory"?: string } };
  steps?: Step[];
};

type Workflow = {
  on?: { push?: { tags?: string[]; branches?: string[] } };
  jobs?: Record<string, Job>;
};

function readWorkflow(): Workflow {
  return existsSync(WORKFLOW) ? parse(readFileSync(WORKFLOW, "utf8")) : {};
}

function needsOf(job: Job | undefined): string[] {
  const needs = job?.needs ?? [];
  return typeof needs === "string" ? [needs] : needs;
}

function stepsOf(job: Job | undefined): Step[] {
  return job?.steps ?? [];
}

/** The folder a step runs in: its own `working-directory`, or the job's default. */
function folderOf(job: Job | undefined, step: Step): string | undefined {
  return step["working-directory"] ?? job?.defaults?.run?.["working-directory"];
}

describe("the release workflow", () => {
  const workflow = readWorkflow();
  const jobs = workflow.jobs ?? {};

  test("runs on version tags only", () => {
    expect(workflow.on?.push?.tags).toEqual(["v*"]);
    expect(workflow.on?.push?.branches).toBeUndefined();
  });

  test("runs the CI workflow", () => {
    expect(jobs.ci?.uses).toBe("./.github/workflows/ci.yml");
  });

  test("checks that the tag matches the CLI's version", () => {
    const runs = stepsOf(jobs["tag-check"]).map(({ run }) => run ?? "");
    expect(runs.some((run) => run.includes("cli/package.json"))).toBe(true);
    expect(runs.some((run) => run.includes("GITHUB_REF_NAME"))).toBe(true);
  });

  test("runs its jobs in order: ci and tag-check, binaries, npm, release", () => {
    expect(Object.keys(jobs).sort()).toEqual(
      ["binaries", "ci", "npm", "release", "tag-check"].sort(),
    );
    expect(needsOf(jobs.ci)).toEqual([]);
    expect(needsOf(jobs["tag-check"])).toEqual([]);
    expect(needsOf(jobs.binaries).sort()).toEqual(["ci", "tag-check"]);
    expect(needsOf(jobs.npm)).toEqual(["binaries"]);
    expect(needsOf(jobs.release)).toEqual(["npm"]);
  });

  test("builds the binaries and writes their checksums", () => {
    const runs = stepsOf(jobs.binaries).map(({ run }) => run ?? "");
    expect(runs.some((run) => run.includes("bun run build-binaries"))).toBe(
      true,
    );
    expect(runs.some((run) => run.includes("SHA256SUMS"))).toBe(true);
  });

  test("publishes to npm from cli/ with provenance, through OIDC", () => {
    const npm = jobs.npm;
    expect(npm?.permissions?.["id-token"]).toBe("write");
    const publish = stepsOf(npm).find(({ run }) =>
      run?.includes("npm publish"),
    );
    expect(publish?.run).toContain("npm publish --provenance --access public");
    expect(publish && folderOf(npm, publish)).toBe("cli");
    expect(JSON.stringify(npm)).not.toContain("NODE_AUTH_TOKEN");
  });

  test("publishes with an npm that supports trusted publishing", () => {
    const setupNode = stepsOf(jobs.npm).find(({ uses }) =>
      uses?.startsWith("actions/setup-node@"),
    );
    const nodeVersion = String(setupNode?.with?.["node-version"] ?? "");
    const upgradesNpm = stepsOf(jobs.npm).some(({ run }) =>
      run?.includes("npm@^11.5.1"),
    );
    expect(nodeVersion === "24" || upgradesNpm).toBe(true);
  });

  test("skips a version npm already has", () => {
    const publish = stepsOf(jobs.npm).find(({ run }) =>
      run?.includes("npm publish"),
    );
    expect(publish?.run).toContain("npm view");
  });

  test("attaches every file in cli/out/ to the GitHub release", () => {
    const release = jobs.release;
    expect(release?.permissions?.contents).toBe("write");
    const runs = stepsOf(release).map(({ run }) => run ?? "");
    expect(
      runs.some((run) => run.includes("gh release") && run.includes("out/*")),
    ).toBe(true);
  });

  test("grants each job only what it needs", () => {
    const writers = Object.entries(jobs).flatMap(([name, job]) =>
      Object.entries(job.permissions ?? {})
        .filter(([, access]) => access === "write")
        .map(([scope]) => `${name}: ${scope}`),
    );
    expect(writers.sort()).toEqual(["npm: id-token", "release: contents"]);
  });
});
