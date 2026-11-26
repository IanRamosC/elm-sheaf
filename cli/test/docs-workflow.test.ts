import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { parse } from "yaml";

const WORKFLOWS = join(import.meta.dir, "../../.github/workflows");

type Step = {
  uses?: string;
  run?: string;
  with?: Record<string, unknown>;
  "working-directory"?: string;
};

type Job = {
  needs?: string | string[];
  if?: string;
  permissions?: Record<string, string>;
  environment?: string | { name?: string };
  steps?: Step[];
};

type Workflow = {
  on?: Record<string, { branches?: string[]; paths?: string[] } | null>;
  concurrency?: { group?: string; "cancel-in-progress"?: boolean };
  permissions?: Record<string, string>;
  jobs?: Record<string, Job>;
};

function readWorkflow(name: string): Workflow {
  return parse(readFileSync(join(WORKFLOWS, name), "utf8"));
}

function stepsOf(job: Job | undefined): Step[] {
  return job?.steps ?? [];
}

/** Every action the workflow uses, as `owner/name@ref`. */
function actionsOf(workflow: Workflow): string[] {
  return Object.values(workflow.jobs ?? {}).flatMap((job) =>
    stepsOf(job).flatMap(({ uses }) => (uses ? [uses] : [])),
  );
}

describe("the docs workflow", () => {
  const workflow = readWorkflow("docs.yml");
  const source = readFileSync(join(WORKFLOWS, "docs.yml"), "utf8");
  const jobs = workflow.jobs ?? {};

  test("deploys from main when the site, the package or the CLI changes, or by hand", () => {
    expect(Object.keys(workflow.on ?? {}).sort()).toEqual([
      "push",
      "workflow_dispatch",
    ]);
    expect(workflow.on?.push?.branches).toEqual(["main"]);
    expect(workflow.on?.push?.paths?.sort()).toEqual(
      ["docs/**", "src/**", "cli/**", ".github/workflows/docs.yml"].sort(),
    );
  });

  test("never runs on pull requests", () => {
    expect(Object.keys(workflow.on ?? {})).not.toContain("pull_request");
    expect(Object.keys(workflow.on ?? {})).not.toContain("pull_request_target");
    expect(jobs.deploy?.if).toBe("github.ref == 'refs/heads/main'");
  });

  test("never cancels a deploy under way", () => {
    expect(workflow.concurrency).toEqual({
      group: "pages",
      "cancel-in-progress": false,
    });
  });

  test("grants each job only what it needs", () => {
    expect(workflow.permissions).toEqual({});
    expect(jobs.build?.permissions).toEqual({ contents: "read" });
    expect(jobs.deploy?.permissions).toEqual({
      pages: "write",
      "id-token": "write",
    });
  });

  test("builds docs/ with the CLI from this commit, and uploads docs/dist", () => {
    const steps = stepsOf(jobs.build);
    const build = steps.find(({ run }) => run?.includes(" build"));
    expect(build?.["working-directory"]).toBe("docs");
    expect(build?.run).toBe("bun ../cli/src/index.ts build");
    const upload = steps.find(({ uses }) =>
      uses?.startsWith("actions/upload-pages-artifact@"),
    );
    expect(upload?.with?.path).toBe("docs/dist");
  });

  test("deploys in the github-pages environment, after the build", () => {
    const deploy = jobs.deploy;
    expect(deploy?.needs).toBe("build");
    const environment = deploy?.environment;
    expect(
      typeof environment === "string" ? environment : environment?.name,
    ).toBe("github-pages");
    expect(
      stepsOf(deploy).some(({ uses }) =>
        uses?.startsWith("actions/deploy-pages@"),
      ),
    ).toBe(true);
  });

  test("pins the Bun and Pages actions by commit, with their version", () => {
    const pinned = actionsOf(workflow).filter((uses) =>
      /^(oven-sh\/setup-bun|actions\/upload-pages-artifact|actions\/deploy-pages)@/.test(
        uses,
      ),
    );
    expect(pinned.length).toBe(3);
    for (const uses of pinned) {
      expect(uses).toMatch(/@[0-9a-f]{40}$/);
      const line = source.split("\n").find((line) => line.includes(uses));
      expect(line).toMatch(/ # v\d+\.\d+\.\d+$/);
    }
  });

  test("sets up Bun with the same pin as the CI workflow", () => {
    const setupBun = (workflow: Workflow) =>
      actionsOf(workflow).filter((uses) =>
        uses.startsWith("oven-sh/setup-bun@"),
      );
    const ci = new Set(setupBun(readWorkflow("ci.yml")));
    expect(ci.size).toBe(1);
    expect(new Set(setupBun(workflow))).toEqual(ci);
  });
});

test("the CI workflow checks the starter and the documentation site", () => {
  const sites = readWorkflow("ci.yml").jobs?.sites;
  expect(
    stepsOf(sites).some(({ run }) => run === "cli/scripts/check-site.sh"),
  ).toBe(true);
});
