import { reconnectable, spawn } from "jsexpect";
import process from "node:process";

export default async function main({ args }) {
  const token = readArg(args, "--token") ?? process.env.EPHEMERAL_TOKEN;
  const managed = reconnectable({
    create: () => spawn(process.execPath, ["./examples/ephemeral-session-terminal.js"], {
      env: {
        ...process.env,
        EPHEMERAL_HOST: "short-lived-app",
        EPHEMERAL_MAX_COMMANDS: "2"
      },
      quiet: args.includes("--quiet")
    }),
    login: (session) => loginWithManualToken(session, token)
  });

  managed.on("reconnect", ({ reconnects }) => {
    console.log(`\n[manager] session closed; reconnecting (${reconnects})`);
  });

  await runCommand(managed, "hostname");
  await runCommand(managed, "tail app.log");
  await runCommand(managed, "whoami");
  await runCommand(managed, "tail app.log");

  await managed.withSession(async (session) => {
    session.sendLine("exit");
    await session.expect("logout", { timeout: 2_000 });
  }, { retries: 0 }).catch(() => {});

  process.exit(0);
}

async function loginWithManualToken(session, token) {
  await session.expect("login:");
  session.sendLine("demo");

  await session.expect("Password:");
  session.sendLine("swordfish");

  await session.expect("RSA token:");

  if (token) {
    session.sendLine(token);
    await session.expect("ephem$ ");
    return;
  }

  console.log("\n[manager] enter any 6-digit RSA token in the child session");
  await session.interactUntil("ephem$ ", { timeout: 60_000 });
}

async function runCommand(managed, command) {
  const result = await managed.withSession(async (session) => {
    session.sendLine(command);

    const hit = await session.expect([
      /([\s\S]*?)ephem\$ /,
      /Session expired by policy/
    ], {
      sinceNow: true,
      timeout: 5_000
    });

    if (/Session expired/.test(hit.text)) {
      throw new Error("PTY exited after session expiry");
    }

    return stripCommandEcho(hit.match[1], command).trim();
  }, { retries: 1 });

  console.log(`\n$ ${command}\n${result}`);
}

function stripCommandEcho(output, command) {
  return output
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(command, "")
    .replace(/\r/g, "");
}

function readArg(args, name) {
  const prefix = `${name}=`;
  const found = args.find((arg) => arg.startsWith(prefix));
  return found?.slice(prefix.length);
}
