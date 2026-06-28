import { spawn } from "jsexpect";

export default async function main({ args }) {
  if (args.length === 0) {
    throw new Error("Usage: jsexpect run examples/ssh-login.js [ssh options...] <user@host>");
  }

  const ssh = spawn("ssh", args);

  while (true) {
    const hit = await ssh.expect([
      /Are you sure you want to continue connecting/i,
      /password:/i,
      /[$#>] ?$/,
      /telehack/i,
      /guest@telehack/i
    ], { timeout: 30_000 });

    if (/continue connecting/i.test(hit.text)) {
      ssh.sendLine("yes");
      continue;
    }

    if (/password:/i.test(hit.text)) {
      const password = process.env.SSH_PASSWORD;
      if (!password) {
        throw new Error("Set SSH_PASSWORD or adjust the example to prompt for it");
      }
      ssh.sendLine(password);
      continue;
    }

    break;
  }

  await ssh.interact();
}
