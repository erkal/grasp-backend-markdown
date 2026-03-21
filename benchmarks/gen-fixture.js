import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const src = resolve("test-project/markdown-example.md");
const dst = resolve("test-project/markdown-example-50x.md");
const one = readFileSync(src, "utf-8");
writeFileSync(dst, Array(50).fill(one).join("\n\n---\n\n"));
