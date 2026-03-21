import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const WARMUP = 5;
const ITERS = 20;

// Load Elm compiled code and eval with correct `this` binding
const elmCode = readFileSync(resolve("build/benchmark.js"), "utf-8");
const elmScope = {};
new Function(elmCode).call(elmScope);
const Elm = elmScope.Elm;

// Load and slice the fixture
const base = readFileSync(resolve("../test-project/markdown-example-50x.md"), "utf-8");
const lines = base.split("\n");
const docs = [
  { name: "1x  (735 lines)", text: lines.slice(0, 735).join("\n") },
  { name: "5x  (3.7K lines)", text: lines.slice(0, 3675).join("\n") },
  { name: "10x (7.4K lines)", text: lines.slice(0, 7350).join("\n") },
  { name: "25x (18K lines)", text: lines.slice(0, 18375).join("\n") },
  { name: "50x (37K lines)", text: base },
];

function pad(s, n) { return s + " ".repeat(Math.max(0, n - s.length)); }

function bench(app, text) {
  return new Promise(resolve => {
    function handler() {
      app.ports.parseResult.unsubscribe(handler);
      resolve(performance.now() - t0);
    }
    app.ports.parseResult.subscribe(handler);
    const t0 = performance.now();
    app.ports.parseThis.send(text);
  });
}

async function main() {
  const app = Elm.Main.init({ flags: null });

  console.log(pad("document", 24) + pad("lines", 10) + pad("median", 12) + pad("min", 10) + "all runs (after warmup)");
  console.log("-".repeat(90));

  for (const doc of docs) {
    for (let i = 0; i < WARMUP; i++) await bench(app, doc.text);

    const times = [];
    for (let i = 0; i < ITERS; i++) times.push(await bench(app, doc.text));

    times.sort((a, b) => a - b);
    const median = times[Math.floor(times.length / 2)];
    const min = times[0];
    const lineCount = doc.text.split("\n").length;

    console.log(
      pad(doc.name, 24) +
      pad(String(lineCount), 10) +
      pad(median.toFixed(1) + " ms", 12) +
      pad(min.toFixed(1) + " ms", 10) +
      times.map(t => t.toFixed(1)).join(", ") + " ms"
    );
  }
}

main().catch(console.error);
