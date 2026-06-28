import { spawn } from "../src/index.js";

const term = spawn(process.execPath, [
  "-e",
  "console.log('JS_EXPECT_SMOKE_OK')"
], { quiet: true });

const hit = await term.expect("JS_EXPECT_SMOKE_OK", { timeout: 5_000 });

term.close();
await Promise.race([
  term.exit,
  new Promise((resolve) => setTimeout(resolve, 1_000))
]);

if (hit.text !== "JS_EXPECT_SMOKE_OK") {
  throw new Error("Smoke test did not match expected terminal output");
}

console.log("smoke ok");
process.exit(0);
