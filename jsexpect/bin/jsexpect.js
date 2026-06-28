#!/usr/bin/env node

import { pathToFileURL } from "node:url";
import path from "node:path";
import process from "node:process";

function usage(exitCode = 0) {
  const out = exitCode === 0 ? process.stdout : process.stderr;
  out.write(`Usage:
  jsexpect run <script.js> [args...]

Scripts must export a default async function.
`);
  process.exit(exitCode);
}

async function main() {
  const [command, script, ...args] = process.argv.slice(2);

  if (command === "--help" || command === "-h") {
    usage(0);
  }

  if (command !== "run" || !script) {
    usage(1);
  }

  const scriptPath = path.resolve(process.cwd(), script);
  const mod = await import(pathToFileURL(scriptPath).href);

  if (typeof mod.default !== "function") {
    throw new Error(`${script} must export a default function`);
  }

  await mod.default({
    args,
    cwd: process.cwd(),
    env: process.env
  });
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  if (typeof error.buffer === "string" && error.buffer.length > 0) {
    process.stderr.write("\n--- terminal buffer tail ---\n");
    process.stderr.write(`${error.buffer.slice(-4000)}\n`);
    process.stderr.write("--- end terminal buffer tail ---\n");
  }
  process.exitCode = 1;
});
