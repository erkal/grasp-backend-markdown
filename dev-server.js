import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { startServer } from "./lib/elm-fs-server/js/server.js";

const PROJECT_DIR = resolve("test-project");
const { port: wsPort } = await startServer(null);

createServer(async (req, res) => {
  if (req.url === "/ws-config") {
    res.end(JSON.stringify({ wsPort, projectDir: PROJECT_DIR }));
    return;
  }
  try {
    const file = resolve("." + (req.url === "/" ? "/index.html" : req.url));
    res.end(await readFile(file));
  } catch {
    res.writeHead(404).end();
  }
}).listen(8015, "127.0.0.1", () => console.log("http://127.0.0.1:8015"));
