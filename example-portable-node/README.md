# example-portable-node

This is a proof of concept for **L4** in [`../readme-claude.md`](../readme-claude.md): running JS/TS on a machine that has no Node.js installed.

It is a small module loader that `bun build --compile` turns into a single native executable. The executable carries its own JavaScript runtime. When it runs, it loads an **external** JS/TS module from disk, next to itself, and calls that module's entry point. The executable therefore works as a "portable node" for a launcher script that ships separately and can be changed without rebuilding the binary.

## What's here

| File | Purpose |
|---|---|
| `src/portable-node-loader.ts` | The loader. It finds `payload.js`, `payload.ts` or `payload.mjs` next to itself, `import()`s it, and calls `run()`. |
| `src/payload.ts` | A sample payload that prints a line. It stands in for the real launcher `.mjs`. |
| `package.json` | Has a `tsc` build for running under regular Node, and `compile:*` scripts that produce the native binaries with Bun. |
| `tsconfig.json` | TypeScript settings (ES2022, NodeNext). |
| `build-binaries.sh` | Cross-compiles all (or the listed) targets into `bin/` and writes `SHA256SUMS`. |

## How it works

- **The payload is not bundled.** The import path is an absolute `file://` URL worked out at runtime, so Bun can't follow it at build time. The payload is read from disk on every run and can be swapped freely.
- **The payload is found next to the executable.** Inside a compiled Bun binary, `import.meta.url` points into Bun's embedded virtual filesystem (`/$bunfs/root/...`). The loader detects that case and looks in `dirname(process.execPath)` instead, which is the folder holding the real binary. When run as plain Node (`node dist/...`), it looks next to the module itself.
- **One source runs in both modes.** The same code works under system Node and as a compiled binary. That's the property the plugin needs: use `node` when it exists, otherwise use the portable binary.

## Build and run

### With system Node (development)
```bash
npm install
npm run build             # tsc → dist/
npm start                 # node dist/portable-node-loader.js (finds dist/payload.js)
```

### As a native executable (requires [Bun](https://bun.sh))

Install Bun if you don't have it:
```bash
curl -fsSL https://bun.sh/install | bash        # macOS / Linux
powershell -c "irm bun.sh/install.ps1 | iex"    # Windows
```

Bun cross-compiles, so all six targets can be built from a single machine. Use whichever of these three options is convenient.

**Option 1: the script** (all targets plus a `SHA256SUMS` file to upload to S3)
```bash
./build-binaries.sh                          # all 6 targets → bin/
./build-binaries.sh darwin-arm64 linux-x64   # only the targets listed
```

**Option 2: npm scripts**
```bash
npm run compile:darwin-arm64     # or any single target
npm run compile:all              # all 6 targets → bin/
```

**Option 3: raw Bun commands**
```bash
bun build src/portable-node-loader.ts --compile --minify --target=bun-darwin-arm64  --outfile bin/portable-node-darwin-arm64
bun build src/portable-node-loader.ts --compile --minify --target=bun-darwin-x64    --outfile bin/portable-node-darwin-x64
bun build src/portable-node-loader.ts --compile --minify --target=bun-linux-arm64   --outfile bin/portable-node-linux-arm64
bun build src/portable-node-loader.ts --compile --minify --target=bun-linux-x64     --outfile bin/portable-node-linux-x64
bun build src/portable-node-loader.ts --compile --minify --target=bun-windows-arm64 --outfile bin/portable-node-windows-arm64.exe
bun build src/portable-node-loader.ts --compile --minify --target=bun-windows-x64   --outfile bin/portable-node-windows-x64.exe
```

Bun also has these target variants:
- `-baseline`, e.g. `bun-linux-x64-baseline`, for older x64 CPUs without AVX2.
- `-musl`, e.g. `bun-linux-x64-musl`, for Alpine and other musl-based Linux.

Binaries for macOS that are built on another OS may need `codesign` before Gatekeeper will run them.

Run a binary with a payload next to it:
```bash
npm run build                          # produces dist/payload.js
cp dist/payload.js bin/
./bin/portable-node-darwin-arm64
# Hello, world!
# Running inside the payload
```

## Targets and sizes

These are measured sizes from the POC build. Nearly all of each file is the embedded Bun runtime; the loader code itself is about 2 KB.

| Target | Size |
|---|---|
| darwin-arm64 | 62 MB |
| darwin-x64 | 69 MB |
| linux-arm64 | 81 MB |
| linux-x64 | 81 MB |
| windows-arm64 | 78 MB |
| windows-x64 | 86 MB |

**Verified:** running on macOS (arm64). The other five binaries build but have not been run yet.

## Next steps (toward the plugin)

- Make the payload the real launcher `.mjs` rather than `payload.*`, either by accepting the path as an argument or by using a fixed name.
- Pass the hook's stdin and stdout through, and propagate the exit code.
- Upload the six binaries to S3 with SHA-256 checksums. The plugin's shell script downloads the matching one when `node` is missing (see the main [`readme-claude.md`](../readme-claude.md)).
