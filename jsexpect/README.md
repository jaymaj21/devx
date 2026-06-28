# jsexpect

An Expect-like terminal automation library for Node.js.

It uses `node-pty`, so the program under automation is attached to a real pseudo-terminal instead of plain stdio. That matters for shells, `ssh`, `sudo`, REPLs, full-screen terminal programs, prompts, echo handling, terminal size, and the final `interact()` handoff.

## Install

```sh
npm install
```

## CLI

Run a script:

```sh
npx jsexpect run examples/ssh-login.js user@example.com
```

Try the public Telehack SSH service:

```sh
node ./bin/jsexpect.js run ./examples/telehack.js
```

Try the local mock login terminal, including a no-echo password prompt:

```sh
node ./bin/jsexpect.js run ./examples/mock-login-expect.js
```

Try the multi-session support-console demo:

```sh
node ./bin/jsexpect.js run ./examples/multi-host-support.js
```

It logs into three local mock hosts, runs checks across all or selected sessions, then offers commands such as `hosts`, `all tail app.log`, `run app-a whoami`, and `attach app-b`.

Try an expiring-session reconnect demo:

```sh
node ./bin/jsexpect.js run ./examples/ephemeral-reconnect-support.js
```

The mock host kills the session after a few commands. The support script detects the closure, restarts the login sequence, pauses at `RSA token:` for manual input, then resumes the interrupted command. For unattended testing, set `EPHEMERAL_TOKEN=123456`.

To run the same demo without typing a token:

```sh
node ./bin/jsexpect.js run ./examples/ephemeral-reconnect-support.js --token=123456
```

Make the executable available globally from this checkout:

```sh
npm link
jsexpect run examples/ssh-login.js user@example.com
```

## Example Commands

On Windows PowerShell, use `npm.cmd` if `npm` is blocked by the execution policy.

Run local checks:

```sh
npm.cmd run check
npm.cmd test
```

Run the shell handoff demo:

```sh
node ./bin/jsexpect.js run ./examples/shell-demo.js
```

Run a normal SSH-style login script:

```sh
node ./bin/jsexpect.js run ./examples/ssh-login.js user@example.com
node ./bin/jsexpect.js run ./examples/ssh-login.js -p 2222 guest@telehack.com
```

Run the Telehack-specific SSH demo:

```sh
node ./bin/jsexpect.js run ./examples/telehack.js
```

Run the mock login terminal directly, without `jsexpect`:

```sh
node ./examples/mock-login-terminal.js
```

Use `demo` as the username and `swordfish` as the password. The password prompt is no-echo.

Run the mock login automation, then drop into `interact()`:

```sh
node ./bin/jsexpect.js run ./examples/mock-login-expect.js
```

Run the mock login automation without interactive handoff:

```sh
node ./bin/jsexpect.js run ./examples/mock-login-expect.js --no-interact
```

Run the multi-host support-console demo:

```sh
node ./bin/jsexpect.js run ./examples/multi-host-support.js
```

Useful commands inside the support console:

```text
hosts
all hostname
all tail app.log
run app-a whoami
run app-c tail app.log
attach app-b
quit
```

Run the multi-host support demo without opening the console:

```sh
node ./bin/jsexpect.js run ./examples/multi-host-support.js --no-interact
```

Run the expiring-session reconnect demo with manual RSA token entry:

```sh
node ./bin/jsexpect.js run ./examples/ephemeral-reconnect-support.js
```

Run the same reconnect demo with a test token supplied on the command line:

```sh
node ./bin/jsexpect.js run ./examples/ephemeral-reconnect-support.js --token=123456
```

Run the reconnect demo quietly, which is useful for automated verification:

```sh
node ./bin/jsexpect.js run ./examples/ephemeral-reconnect-support.js --quiet --token=123456
```

## Script API

Scripts are plain JavaScript modules that export a default async function.

```js
import { spawn } from "jsexpect";

export default async function main({ args }) {
  const ssh = spawn("ssh", [args[0]]);

  const hit = await ssh.expect([
    /password:/i,
    /Are you sure you want to continue connecting/i,
    /[$#] $/
  ], { timeout: 30_000 });

  if (/continue connecting/i.test(hit.text)) {
    ssh.sendLine("yes");
    await ssh.expect(/password:/i);
  }

  if (/password:/i.test(hit.text)) {
    ssh.sendLine(process.env.SSH_PASSWORD ?? "");
  }

  await ssh.expect(/[$#] $/);
  ssh.sendLine("stty -a");

  await ssh.interact();
}
```

## Programmer's Guide

A `jsexpect` script is an ES module. Export one async default function; the CLI calls it with `{ args, cwd, env }`.

```js
import { spawn } from "jsexpect";

export default async function main({ args, env }) {
  const session = spawn("ssh", args, { env });

  await session.expect("Password:");
  session.sendLine(env.SSH_PASSWORD);

  await session.expect(/[$#>] ?$/);
  await session.interact();
}
```

Use `spawn(command, args, options)` when you know the program to start. The child gets a real PTY, so terminal-aware programs see a terminal, can turn echo on/off, receive resize events during `interact()`, and behave like interactive commands rather than pipe-driven commands.

### Waiting For Output

`expect()` accepts a string, regex, predicate, or an array of those patterns.

```js
const hit = await session.expect([
  /Are you sure you want to continue connecting/i,
  /password:/i,
  /[$#>] ?$/
], { timeout: 30_000 });

if (hit.index === 0) {
  session.sendLine("yes");
}
```

The returned object includes the matched `index`, `text`, `pattern`, full `buffer`, elapsed time, and regex `match`/`groups` when applicable.

Use `{ sinceNow: true }` when matching the response to a command you just sent, so old buffered output cannot satisfy the new wait.

```js
session.sendLine("tail app.log");
const hit = await session.expect(/([\s\S]*?)mock\$ /, {
  sinceNow: true,
  timeout: 5_000
});
console.log(hit.match[1]);
```

### Sending Input

Use `send()` for raw bytes and `sendLine()` for ordinary line-oriented prompts.

```js
session.send("y");
session.sendLine("demo");
```

`sendLine()` writes `\r`, which is the right return key behavior for most PTY programs.

### Handoff To The User

Use `interact()` when automation is done and the human should control the session directly.

```js
await session.expect(/[$#>] ?$/);
await session.interact();
```

During `interact()`, local stdin is put into raw mode when possible, local terminal resize events are forwarded, and bytes flow directly between the user and child PTY.

### Manual Token Or MFA Prompts

Use `interactUntil()` when automation should pause for a human-entered challenge and then continue after a known prompt appears.

```js
await session.expect("RSA token:");
console.log("Enter the RSA token in the child session");
await session.interactUntil("app$ ", { timeout: 60_000 });

session.sendLine("tail app.log");
```

This is useful when policy requires the operator to type a token manually and the script must not collect or store it.

### Multiple Sessions

Each `spawn()` call creates an independent PTY. Use `Promise.all()` to log in or run checks concurrently.

```js
const sessions = await Promise.all(hosts.map(async (host) => {
  const session = spawn("ssh", [host]);
  await login(session);
  return { host, session };
}));

await Promise.all(sessions.map(({ session }) => {
  session.sendLine("hostname");
  return session.expect(/([\s\S]*?)[$#>] ?$/, { sinceNow: true });
}));
```

The multi-host support demo in `examples/multi-host-support.js` shows this pattern with selective `attach <host>` handoff.

### Reconnecting Expired Sessions

Use `reconnectable({ create, login })` when hosts close sessions periodically. Keep session creation and login replay in one place, then run work through `withSession()`.

```js
import { reconnectable, spawn } from "jsexpect";

const managed = reconnectable({
  create: () => spawn("ssh", ["app01"]),
  login: async (session) => {
    await session.expect("Password:");
    session.sendLine(process.env.APP_PASSWORD);
    await session.expect("RSA token:");
    await session.interactUntil("app$ ", { timeout: 60_000 });
  }
});

await managed.withSession(async (session) => {
  session.sendLine("tail app.log");
  return session.expect(/([\s\S]*?)app\$ /, { sinceNow: true });
}, { retries: 1 });
```

If the PTY exits while work is waiting for output, `withSession()` can reconnect and retry the operation. The expiring-session demo in `examples/ephemeral-reconnect-support.js` shows this end to end.

### Detecting Session Closure

At the low level, a `TerminalSession` exposes session closure in three ways.

```js
session.once("exit", (event) => {
  console.log(event.exitCode, event.signal);
});

if (session.closed) {
  console.log("session is already closed");
}

const event = await session.exit;
```

Operations that are waiting on a live child terminal reject with `SessionClosedError` if the PTY exits first.

```js
import { SessionClosedError, spawn } from "jsexpect";

try {
  await session.expect("app$ ");
} catch (error) {
  if (error instanceof SessionClosedError) {
    console.log("session closed", error.exitCode, error.signal);
  } else {
    throw error;
  }
}
```

`reconnectable().withSession()` uses this same interface. If your work callback fails with `SessionClosedError`, or the session is already marked closed, `withSession()` can reconnect, replay the `login` function, and retry the work callback.

```js
managed.on("reconnect", ({ reason, reconnects }) => {
  console.log("reconnect", reconnects, reason);
});
```

### Practical Notes

- Prefer explicit prompts in regexes, such as `/mock\$ /` or `/[$#>] ?$/`.
- Use timeouts around every wait that depends on the remote side.
- Use `{ quiet: true }` when collecting output for a support tool, and the default output mirroring when the operator should see the terminal state.
- Avoid logging passwords or tokens. For manual MFA, prefer `interactUntil()` over reading the token into your script.
- Always close or log out sessions you no longer need.

## Core Methods

- `spawn(command, args, options)` starts a child in a PTY.
- `expect(patternOrPatterns, options)` waits for a string, regex, predicate, or array of them.
- `send(text)` writes raw text to the child terminal.
- `sendLine(text)` writes text plus `\r`.
- `interact(options)` connects your terminal directly to the child PTY, forwards resize events, puts stdin in raw mode when possible, and resolves when the child exits.
- `interactUntil(patternOrPatterns, options)` temporarily gives the child terminal to the human, then returns to automation when expected output appears. This is useful for RSA token, MFA, or other manual challenge prompts.
- `close()` kills the child.
- `reconnectable({ create, login })` wraps a session factory and login sequence so work can reconnect and retry after session closure.
- `SessionClosedError` is thrown by wait-style operations when the PTY exits before the operation completes.

Child output is mirrored to stdout by default so the local terminal keeps the same screen state the child terminal has. Pass `{ quiet: true }` to `spawn()` if a script should collect output without displaying it before `interact()`.

## Why `interact()` Is The Important Part

After automation has done its job, `interact()` stops filtering the terminal stream and turns the process into a direct pass-through:

- child PTY output goes to local stdout;
- local stdin bytes go straight to the child PTY;
- local terminal raw mode is enabled while interacting;
- `SIGWINCH`/stdout resize changes are propagated to the child PTY;
- raw mode and listeners are restored on exit.

That gives the same practical workflow as Tcl Expect: automate login/setup, then hand the terminal back to the human.
