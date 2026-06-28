import { spawn } from "jsexpect";

export default async function main() {
  const ssh = spawn("ssh", [
    "-o",
    "ConnectTimeout=15",
    "-p",
    "2222",
    "guest@telehack.com"
  ]);

  while (true) {
    const hit = await ssh.expect([
      /Are you sure you want to continue connecting/i,
      /telehack/i,
      /guest@telehack/i,
      /connection timed out/i,
      /connection refused/i,
      /could not resolve/i,
      /no route to host/i,
      /network is unreachable/i,
      /operation timed out/i,
      /> ?$/,
      /\.\s*$/
    ], { timeout: 30_000 });

    if (/continue connecting/i.test(hit.text)) {
      ssh.sendLine("yes");
      continue;
    }

    if (/timed out|refused|could not resolve|no route|network is unreachable/i.test(hit.text)) {
      throw new Error(`SSH connection failed: ${hit.text}`);
    }

    break;
  }

  await ssh.interact();
}
