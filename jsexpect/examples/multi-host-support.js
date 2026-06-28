import { spawn } from "jsexpect";
import process from "node:process";
import readline from "node:readline/promises";

const hosts = [
  { name: "app-a", queueDepth: "3" },
  { name: "app-b", queueDepth: "0" },
  { name: "app-c", queueDepth: "17" }
];

export default async function main({ args }) {
  const sessions = await Promise.all(hosts.map(login));

  await runOnAll(sessions, "hostname");
  await runOnSelected(sessions, ["app-a", "app-c"], "tail app.log");

  if (args.includes("--no-interact")) {
    await shutdown(sessions);
    process.exit(0);
    return;
  }

  await supportConsole(sessions);
}

async function login(host) {
  const session = spawn(process.execPath, ["./examples/mock-login-terminal.js"], {
    env: {
      ...process.env,
      MOCK_HOST: host.name,
      MOCK_QUEUE_DEPTH: host.queueDepth
    },
    quiet: true
  });

  await session.expect("MockTTY login:");
  session.sendLine("demo");

  await session.expect("Password:");
  session.sendLine("swordfish");

  await session.expect("mock$ ");

  return { ...host, session };
}

async function runOnAll(sessions, command) {
  console.log(`\n== ${command} on all sessions ==`);
  await Promise.all(sessions.map((host) => runCommand(host, command)));
}

async function runOnSelected(sessions, names, command) {
  console.log(`\n== ${command} on ${names.join(", ")} ==`);
  const wanted = new Set(names);
  await Promise.all(
    sessions
      .filter((host) => wanted.has(host.name))
      .map((host) => runCommand(host, command))
  );
}

async function runCommand(host, command) {
  host.session.sendLine(command);
  const hit = await host.session.expect(/([\s\S]*?)mock\$ /, {
    sinceNow: true,
    timeout: 5_000
  });

  const output = stripCommandEcho(hit.match[1], command).trim();
  console.log(`[${host.name}] ${output || "(no output)"}`);
}

async function supportConsole(sessions) {
  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  try {
    printHelp();

    while (true) {
      const line = (await rl.question("support> ")).trim();
      const [command, ...rest] = line.split(/\s+/);

      if (command === "quit" || command === "exit") {
        break;
      }

      if (command === "hosts") {
        console.log(sessions.map((host) => host.name).join("\n"));
        continue;
      }

      if (command === "all" && rest.length > 0) {
        await runOnAll(sessions, rest.join(" "));
        continue;
      }

      if (command === "run" && rest.length > 1) {
        const [name, ...commandParts] = rest;
        const host = findHost(sessions, name);
        await runCommand(host, commandParts.join(" "));
        continue;
      }

      if (command === "attach" && rest.length === 1) {
        const host = findHost(sessions, rest[0]);
        console.log(`Attaching to ${host.name}. Type exit to close that mock session.`);
        await host.session.interact();
        continue;
      }

      printHelp();
    }
  } finally {
    rl.close();
    await shutdown(sessions);
  }
}

async function shutdown(sessions) {
  await Promise.all(sessions.map(async (host) => {
    if (!host.session.closed) {
      host.session.sendLine("exit");
      await host.session.expect("logout", { timeout: 2_000 }).catch(() => {});
      await Promise.race([
        host.session.exit,
        new Promise((resolve) => setTimeout(resolve, 1_000))
      ]);
    }
  }));
}

function findHost(sessions, name) {
  const host = sessions.find((candidate) => candidate.name === name);
  if (!host) {
    throw new Error(`Unknown host: ${name}`);
  }
  return host;
}

function stripCommandEcho(output, command) {
  return output
    .replace(/\x1B\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(command, "")
    .replace(/\r/g, "");
}

function printHelp() {
  console.log(`
Commands:
  hosts
  all <command>
  run <host> <command>
  attach <host>
  quit

Mock host commands:
  hostname
  tail app.log
  whoami
  help
`);
}
