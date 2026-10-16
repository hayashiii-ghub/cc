import { watch, type FSWatcher } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parsePort, serveSite } from "./serve.ts";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
let activeBuild: ReturnType<typeof Bun.spawn> | undefined;
let server: Awaited<ReturnType<typeof serveSite>> | undefined;
let watchers: FSWatcher[] = [];
let building = false;
let pending = false;
let timer: ReturnType<typeof setTimeout> | undefined;

async function build(): Promise<boolean> {
  activeBuild = Bun.spawn([process.execPath, "scripts/build.ts"], { cwd: root, stdout: "inherit", stderr: "inherit" });
  const success = await activeBuild.exited === 0;
  activeBuild = undefined;
  return success;
}

async function rebuild(): Promise<void> {
  if (building) { pending = true; return; }
  building = true;
  try {
    do {
      pending = false;
      if (await build()) console.log("Rebuilt site. Reload the browser to see changes.");
    } while (pending);
  } finally {
    building = false;
  }
}

function stop(): void {
  clearTimeout(timer);
  watchers.forEach((watcher) => watcher.close());
  activeBuild?.kill();
  server?.stop(true);
  process.exit(0);
}
process.once("SIGINT", stop);
process.once("SIGTERM", stop);

if (!(await build())) throw new Error("Initial site build failed");
server = await serveSite(parsePort());
watchers = ["src", "public"].map((directory) => watch(join(root, directory), { recursive: true }, () => {
  clearTimeout(timer);
  timer = setTimeout(() => { void rebuild(); }, 100);
}));
