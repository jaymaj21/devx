#!/usr/bin/env node

import process from "node:process";

const expectedUser = "demo";
const expectedPassword = "swordfish";

process.stdout.write("MockTTY login: ");
const username = await readLine({ echo: true });

process.stdout.write("Password: ");
const password = await readLine({ echo: false });
process.stdout.write("\r\n");

if (username !== expectedUser || password !== expectedPassword) {
  process.stdout.write("Login incorrect\r\n");
  process.exit(1);
}

process.stdout.write("Welcome to MockTTY\r\n");
process.stdout.write("mock$ ");

while (true) {
  const line = await readLine({ echo: true });
  const command = line.trim();

  if (command === "exit" || command === "logout") {
    process.stdout.write("logout\r\n");
    process.exit(0);
  }

  if (command === "whoami") {
    process.stdout.write(`${expectedUser}\r\n`);
  } else if (command === "hostname") {
    process.stdout.write(`${process.env.MOCK_HOST ?? "mock-host"}\r\n`);
  } else if (command === "tail app.log") {
    process.stdout.write(`[${process.env.MOCK_HOST ?? "mock-host"}] INFO service healthy\r\n`);
    process.stdout.write(`[${process.env.MOCK_HOST ?? "mock-host"}] INFO queue depth ${process.env.MOCK_QUEUE_DEPTH ?? "0"}\r\n`);
  } else if (command === "help") {
    process.stdout.write("Commands: help, hostname, tail app.log, whoami, exit\r\n");
  } else if (command.length > 0) {
    process.stdout.write(`mock: ${command}: command not found\r\n`);
  }

  process.stdout.write("mock$ ");
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

        value += String.fromCharCode(byte);
        if (echo) {
          process.stdout.write(String.fromCharCode(byte));
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
