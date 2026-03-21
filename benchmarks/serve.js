import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { exec } from "node:child_process";

const ROOT = resolve("..");

const server = createServer(async (req, res) => {
  try {
    const file = resolve(ROOT + (req.url === "/" ? "/benchmarks/index.html" : req.url));
    res.end(await readFile(file));
  } catch {
    res.writeHead(404).end();
  }
});

// Port 0 = OS picks a free port
server.listen(0, "127.0.0.1", () => {
  const url = `http://127.0.0.1:${server.address().port}`;
  console.log(url);
  exec(`sh ../scripts/open-if-not-open.sh ${url}`);
});
