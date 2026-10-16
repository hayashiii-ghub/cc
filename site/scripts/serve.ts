import { realpath, stat } from "node:fs/promises";
import { dirname, extname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const distRoot = resolve(dirname(fileURLToPath(import.meta.url)), "../dist");
const mimeTypes: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".webp": "image/webp",
  ".ico": "image/x-icon",
  ".woff2": "font/woff2",
  ".txt": "text/plain; charset=utf-8",
};

export function parsePort(args = process.argv.slice(2)): number {
  if (args.length === 0) return 3000;
  const value = args.length === 2 && args[0] === "--port" ? args[1]
    : args.length === 1 && args[0]?.startsWith("--port=") ? args[0].slice(7) : "";
  const port = Number(value);
  if (!value || !/^\d+$/.test(value) || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("Usage: bun scripts/serve.ts [--port 3000]");
  }
  return port;
}

export async function createStaticHandler(directory = distRoot) {
  const root = await realpath(directory);
  return async (request: Request): Promise<Response> => {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    let pathname: string;
    try {
      // Read before URL normalization so encoded traversal is rejected as well.
      const raw = request.url.replace(/^[a-z][a-z\d+.-]*:\/\/[^/]+/i, "").split(/[?#]/, 1)[0] || "/";
      pathname = decodeURIComponent(raw);
    } catch {
      return new Response("Bad request", { status: 400 });
    }
    if (!pathname.startsWith("/") || pathname.includes("\\") || pathname.includes("\0")
      || pathname.split("/").some((part) => part === ".." || part === ".")) {
      return new Response("Forbidden", { status: 403 });
    }
    const path = resolve(root, `.${pathname === "/" ? "/index.html" : pathname}`);
    try {
      const target = await realpath(path);
      if (!target.startsWith(root + sep)) return new Response("Forbidden", { status: 403 });
      const info = await stat(target);
      if (!info.isFile()) return new Response("Not found", { status: 404 });
      return new Response(request.method === "HEAD" ? null : Bun.file(target), {
        headers: {
          "Content-Type": mimeTypes[extname(target).toLowerCase()] ?? "application/octet-stream",
          "Content-Length": String(info.size),
          "Cache-Control": "no-cache",
          "X-Content-Type-Options": "nosniff",
        },
      });
    } catch {
      return new Response("Not found", { status: 404 });
    }
  };
}

export async function serveSite(port = 3000) {
  if (!(await Bun.file(join(distRoot, "index.html")).exists())) throw new Error("Run bun run build before starting the site.");
  const server = Bun.serve({ hostname: "127.0.0.1", port, fetch: await createStaticHandler() });
  console.log(`Site available at ${server.url.href}`);
  return server;
}

if (import.meta.main) await serveSite(parsePort());
