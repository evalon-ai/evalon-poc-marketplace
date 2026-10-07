import { existsSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

type Payload = { run: () => void };

/**
 * Directory to look for the external payload in.
 *
 * In a Bun `--compile` standalone binary, `import.meta.url` resolves into
 * Bun's embedded virtual filesystem (e.g. `/$bunfs/root`), so we instead
 * resolve next to the real executable on disk (`process.execPath`). In dev
 * (node src/index.ts or node dist/index.js) we resolve next to this module.
 */
function payloadDir(): string {
  const url = import.meta.url;
  const isStandalone =
    url.includes("$bunfs") || url.includes("~BUN") || url.includes("B:~BUN");
  if (isStandalone) {
    return dirname(process.execPath);
  }
  return dirname(fileURLToPath(url));
}

/**
 * Load the payload's entry point from an external file next to us.
 *
 * The import specifier is computed at runtime (an absolute file:// URL), so
 * Bun does NOT bundle the payload into the executable — it is resolved from
 * disk when the launcher runs, and can be swapped without rebuilding.
 */
async function loadPayload(): Promise<Payload> {
  const dir = payloadDir();

  for (const ext of [".js", ".ts", ".mjs"]) {
    const candidate = join(dir, `payload${ext}`);
    if (existsSync(candidate)) {
      const mod = await import(pathToFileURL(candidate).href);
      return mod as Payload;
    }
  }

  throw new Error(`No payload (payload.js/.ts) found next to the launcher in ${dir}`);
}

async function main(): Promise<void> {
  console.log("Hello, world!");

  // Dynamically load the external payload module and run its entry point.
  const payload = await loadPayload();
  payload.run();
}

main();
