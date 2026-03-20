// Dev server: serves static files, lists test-project .md files, handles saves.

import express from "express";
import { readdir, readFile, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const PORT = 8015;
const PROJECT_DIR = resolve("test-project");

const app = express();

app.use(express.json());
app.use(express.static(".", { maxAge: 0, dotfiles: "deny" }));

app.get("/files", async (_req, res) => {
  try {
    const entries = await readdir(PROJECT_DIR);
    const mdFiles = entries.filter(f => f.endsWith(".md")).sort();
    res.json(mdFiles);
  } catch (err) {
    console.error("[files] Failed to list directory:", err.message);
    res.status(500).json({ error: err.message });
  }
});

app.get("/files/:name", async (req, res) => {
  const resolved = resolve(PROJECT_DIR, req.params.name);

  if (!resolved.startsWith(PROJECT_DIR + "/") || !resolved.endsWith(".md")) {
    return res.status(403).json({ error: "Path outside allowed scope" });
  }

  try {
    const content = await readFile(resolved, "utf-8");
    res.type("text/plain").send(content);
  } catch (err) {
    const status = err.code === "ENOENT" ? 404 : 500;
    console.error(`[files/:name] Failed to read ${resolved}:`, err.message);
    res.status(status).json({ error: err.message });
  }
});

app.post("/save", async (req, res) => {
  if (!req.body || typeof req.body !== "object") {
    return res.status(400).json({ error: "Invalid request body" });
  }

  const { path: filePath, content } = req.body;

  if (typeof filePath !== "string" || typeof content !== "string") {
    return res.status(400).json({ error: "Missing path or content" });
  }

  const resolved = resolve(PROJECT_DIR, filePath);

  if (!resolved.startsWith(PROJECT_DIR + "/") || !resolved.endsWith(".md")) {
    return res.status(403).json({ error: "Path outside allowed scope" });
  }

  try {
    await writeFile(resolved, content, "utf-8");
    res.json({ ok: true });
  } catch (err) {
    console.error(`[save] Failed to write ${resolved}:`, err.message);
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, "127.0.0.1", () => {
  console.log(`Server listening on http://localhost:${PORT}`);
});
