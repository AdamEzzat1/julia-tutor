// Static server for the rendered site (site/_site), mounted under /julia-tutor/
// like GitHub Pages serves a project site, so relative links are tested the way
// they will be deployed. Usage: node scripts/serve.mjs [port]
import { createServer } from "node:http";
import { readFile, stat } from "node:fs/promises";
import { extname, join, normalize, resolve } from "node:path";

const root = resolve(import.meta.dirname, "../../site/_site");
const port = Number(process.argv[2] ?? 4321);
const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript", ".css": "text/css",
  ".json": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".woff2": "font/woff2" };

createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://x");
  if (url.pathname === "/" ) { res.writeHead(302, { location: "/julia-tutor/" }); return res.end(); }
  if (!url.pathname.startsWith("/julia-tutor/")) { res.writeHead(404); return res.end("not found"); }
  let p = normalize(join(root, decodeURIComponent(url.pathname.slice("/julia-tutor".length))));
  if (!p.startsWith(root)) { res.writeHead(403); return res.end(); }
  try {
    if ((await stat(p)).isDirectory()) p = join(p, "index.html");
    const body = await readFile(p);
    res.writeHead(200, { "content-type": types[extname(p)] ?? "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404); res.end("not found");
  }
}).listen(port, () => console.log(`serving ${root} at http://localhost:${port}/julia-tutor/`));
