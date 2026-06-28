#!/usr/bin/env node

import process from "node:process";

const host = process.env.EPHEMERAL_HOST ?? "ephemeral-host";
const expectedUser = "demo";
const expectedPassword = "swordfish";
const maxCommands = Number.parseInt(process.env.EPHEMERAL_MAX_COMMANDS ?? "2", 10);

let commandCount = 0;

process.stdout.write(`${host} login: `);
const username = await readLine({ echo: true });

process.stdout.write("Password: ");
const password = await readLine({ echo: false });
process.stdout.write("\r\n");

process.stdout.write("RSA token: ");
const token = await readLine({ echo: false });
process.stdout.write("\r\n");

if (username !== expectedUser || password !== expectedPassword || !/^\d{6}$/.test(token)) {
  process.stdout.write("Access denied\r\n");
  process.exit(1);
}

process.stdout.write(`Welcome to ${host}\r\n`);
prompt();

while (true) {
  const line = await readLine({ echo: true });
  const command = line.trim();

  if (command === "exit" || command === "logout") {
    process.stdout.write("logout\r\n");
    process.exit(0);
  }

  commandCount += 1;

  if (commandCount > maxCommands) {
    process.stdout.write("Session expired by policy\r\n");
    process.exit(0);
  }

  if (command === "hostname") {
    process.stdout.write(`${host}\r\n`);
  } else if (command === "tail app.log") {
    process.stdout.write(`[${host}] INFO application healthy\r\n`);
    process.stdout.write(`[${host}] INFO token-authenticated session ${process.pid}\r\n`);
  } else if (command === "whoami") {
    process.stdout.write(`${expectedUser}\r\n`);
  } else if (command === "help") {
    process.stdout.write("Commands: help, hostname, tail app.log, whoami, exit\r\n");
  } else if (command.length > 0) {
    process.stdout.write(`${host}: ${command}: command not found\r\n`);
  }

  prompt();
}

function prompt() {
  process.stdout.write("ephem$ ");
}

function readLine({ echo }) {
  return new Promise((resolve) => {
    let value = "";
    const stdin = process.stdin;
    const previousRawMode = stdin.isRaw;
    const canSetRawMode = typeof stdin.setRawMode === "function" && stdin.isTTY;

    const cleanup = () => {
      stdin.off("data", onData);
      if (canSetRawMode) {
        stdin.setRawMode(Boolean(previousRawMode));
      }
      stdin.pause();
    };

    const finish = () => {
      cleanup();
      resolve(value);
    };

    const onData = (chunk) => {
      for (const byte of chunk) {
        if (byte === 3) {
          process.exit(130);
        }

        if (byte === 13 || byte === 10) {
          if (echo) {
            process.stdout.write("\r\n");
          }
          finish();
          return;
        }

        if (byte === 8 || byte === 127) {
          if (value.length > 0) {
            value = value.slice(0, -1);
            if (echo) {
              process.stdout.write("\b \b");
            }
          }
          continue;
        }

        const char = String.fromCharCode(byte);
        value += char;
        if (echo) {
          process.stdout.write(char);
        }
      }
    };

    if (canSetRawMode) {
      stdin.setRawMode(true);
    }
    stdin.resume();
    stdin.on("data", onData);
  });
}
