import { shell } from "jsexpect";

export default async function main() {
  const term = shell();

  await term.expect(/[>$#] ?$/);
  term.sendLine("echo automated setup complete");
  await term.expect("automated setup complete");

  await term.interact();
}
