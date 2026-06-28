import { spawn } from "jsexpect";

export default async function main({ args }) {
  const login = spawn(process.execPath, ["./examples/mock-login-terminal.js"]);

  await login.expect("MockTTY login:");
  login.sendLine("demo");

  await login.expect("Password:");
  login.sendLine("swordfish");

  await login.expect("mock$ ");
  login.sendLine("whoami");
  await login.expect(/demo\r?\n/);

  if (args.includes("--no-interact")) {
    await login.expect("mock$ ");
    login.sendLine("exit");
    await login.expect("logout");
    login.close();
    return;
  }

  await login.interact();
}
