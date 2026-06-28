import os from "node:os";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { EventEmitter } from "node:events";
import pty from "node-pty";

const DEFAULT_TIMEOUT = 10_000;

export class ExpectTimeoutError extends Error {
  constructor(timeout, buffer) {
    super(`Timed out after ${timeout}ms waiting for expected terminal output`);
    this.name = "ExpectTimeoutError";
    this.timeout = timeout;
    this.buffer = buffer;
  }
}

export class SessionClosedError extends Error {
  constructor(event, message = "PTY session closed") {
    const exitCode = event?.exitCode;
    const signal = event?.signal;
    super(`${message}: exitCode=${exitCode}, signal=${signal}`);
    this.name = "SessionClosedError";
    this.event = event;
    this.exitCode = exitCode;
    this.signal = signal;
  }
}

export class TerminalSession extends EventEmitter {
  #pty;
  #buffer = "";
  #maxBuffer;
  #closed = false;
  #exit;
  #exitPromise;
  #outputDisposer;
  #logOutput;

  constructor(command, args = [], options = {}) {
    super();

    const stdin = options.stdin ?? process.stdin;
    const stdout = options.stdout ?? process.stdout;

    this.#maxBuffer = options.maxBuffer ?? 128 * 1024;
    this.stdin = stdin;
    this.stdout = stdout;
    this.#logOutput = options.quiet ? undefined : (options.output ?? stdout);

    this.#pty = pty.spawn(resolveCommand(command, options.env ?? process.env), args, {
      name: options.term ?? process.env.TERM ?? "xterm-256color",
      cols: options.cols ?? stdout.columns ?? 80,
      rows: options.rows ?? stdout.rows ?? 24,
      cwd: options.cwd ?? process.cwd(),
      env: options.env ?? process.env,
      handleFlowControl: options.handleFlowControl ?? false
    });

    this.#exitPromise = new Promise((resolve) => {
      this.#exit = resolve;
    });

    this.#outputDisposer = this.#pty.onData((chunk) => {
      this.#append(chunk);
      this.#logOutput?.write(chunk);
      this.emit("data", chunk);
    });

    this.#pty.onExit((event) => {
      this.#closed = true;
      this.#outputDisposer?.dispose();
      this.emit("exit", event);
      this.#exit(event);
    });
  }

  get pid() {
    return this.#pty.pid;
  }

  get closed() {
    return this.#closed;
  }

  get buffer() {
    return this.#buffer;
  }

  get exit() {
    return this.#exitPromise;
  }

  send(text) {
    this.#assertOpen();
    this.#pty.write(String(text));
    return this;
  }

  sendLine(text = "") {
    return this.send(`${text}\r`);
  }

  resize(cols = this.stdout.columns, rows = this.stdout.rows) {
    if (!this.#closed && cols && rows) {
      this.#pty.resize(cols, rows);
    }
  }

  close(signal) {
    if (!this.#closed) {
      this.#pty.kill(signal);
    }
  }

  expect(patterns, options = {}) {
    this.#assertOpen();

    const choices = Array.isArray(patterns) ? patterns : [patterns];
    const timeout = options.timeout ?? DEFAULT_TIMEOUT;
    const sinceNow = options.sinceNow ?? false;
    const startedAt = Date.now();
    let searchBuffer = sinceNow ? "" : this.#buffer;
    let timer;
    let onData;
    let onExit;

    return new Promise((resolve, reject) => {
      const cleanup = () => {
        clearTimeout(timer);
        this.off("data", onData);
        this.off("exit", onExit);
      };

      const check = () => {
        const match = findMatch(searchBuffer, choices);
        if (!match) {
          return false;
        }

        cleanup();
        resolve({
          ...match,
          buffer: searchBuffer,
          elapsed: Date.now() - startedAt
        });
        return true;
      };

      onData = (chunk) => {
        searchBuffer += chunk;
        if (searchBuffer.length > this.#maxBuffer) {
          searchBuffer = searchBuffer.slice(-this.#maxBuffer);
        }
        check();
      };

      onExit = (event) => {
        cleanup();
        reject(new SessionClosedError(event, "PTY exited before expected output arrived"));
      };

      timer = setTimeout(() => {
        cleanup();
        reject(new ExpectTimeoutError(timeout, searchBuffer));
      }, timeout);

      this.on("data", onData);
      this.once("exit", onExit);
      check();
    });
  }

  interact(options = {}) {
    this.#assertOpen();

    const stdin = options.stdin ?? this.stdin;
    const stdout = options.stdout ?? this.stdout;
    const exitOnEscape = options.escape;
    const previousLogOutput = this.#logOutput;

    return new Promise((resolve, reject) => {
      const previousRawMode = stdin.isRaw;
      const hadRawMode = typeof stdin.setRawMode === "function";
      let settled = false;

      const cleanup = () => {
        this.off("exit", onExit);
        stdin.off("data", onStdinData);
        stdout.off?.("resize", onResize);
        this.#logOutput = previousLogOutput;
        if (hadRawMode) {
          stdin.setRawMode(Boolean(previousRawMode));
        }
        stdin.pause();
      };

      const settle = (callback, value) => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        callback(value);
      };

      const onStdinData = (chunk) => {
        if (exitOnEscape && chunk.equals(Buffer.from(exitOnEscape))) {
          settle(resolve, { escaped: true });
          return;
        }
        this.#pty.write(chunk.toString("utf8"));
      };

      const onResize = () => {
        this.resize(stdout.columns, stdout.rows);
      };

      const onExit = (event) => {
        settle(resolve, event);
      };

      try {
        this.resize(stdout.columns, stdout.rows);
        this.#logOutput = stdout;
        this.once("exit", onExit);
        stdout.on?.("resize", onResize);

        if (hadRawMode) {
          stdin.setRawMode(true);
        }
        stdin.resume();
        stdin.on("data", onStdinData);
      } catch (error) {
        settle(reject, error);
      }

      if (this.#closed) {
        settle(resolve, { exitCode: undefined, signal: undefined });
      }
    });
  }

  interactUntil(patterns, options = {}) {
    this.#assertOpen();

    const stdin = options.stdin ?? this.stdin;
    const stdout = options.stdout ?? this.stdout;
    const choices = Array.isArray(patterns) ? patterns : [patterns];
    const timeout = options.timeout ?? DEFAULT_TIMEOUT;
    const exitOnEscape = options.escape;
    const previousLogOutput = this.#logOutput;
    let searchBuffer = "";

    return new Promise((resolve, reject) => {
      const previousRawMode = stdin.isRaw;
      const hadRawMode = typeof stdin.setRawMode === "function";
      let timer;
      let settled = false;

      const cleanup = () => {
        clearTimeout(timer);
        this.off("data", onPtyData);
        this.off("exit", onExit);
        stdin.off("data", onStdinData);
        stdout.off?.("resize", onResize);
        this.#logOutput = previousLogOutput;
        if (hadRawMode) {
          stdin.setRawMode(Boolean(previousRawMode));
        }
        stdin.pause();
      };

      const settle = (callback, value) => {
        if (settled) {
          return;
        }
        settled = true;
        cleanup();
        callback(value);
      };

      const check = () => {
        const match = findMatch(searchBuffer, choices);
        if (match) {
          settle(resolve, { ...match, buffer: searchBuffer });
        }
      };

      const onPtyData = (chunk) => {
        searchBuffer += chunk;
        if (searchBuffer.length > this.#maxBuffer) {
          searchBuffer = searchBuffer.slice(-this.#maxBuffer);
        }
        check();
      };

      const onStdinData = (chunk) => {
        if (exitOnEscape && chunk.equals(Buffer.from(exitOnEscape))) {
          settle(resolve, { escaped: true });
          return;
        }
        this.#pty.write(chunk.toString("utf8"));
      };

      const onResize = () => {
        this.resize(stdout.columns, stdout.rows);
      };

      const onExit = (event) => {
        settle(reject, new SessionClosedError(event, "PTY exited during interactUntil"));
      };

      try {
        this.resize(stdout.columns, stdout.rows);
        this.#logOutput = stdout;
        this.on("data", onPtyData);
        this.once("exit", onExit);
        stdout.on?.("resize", onResize);

        if (hadRawMode) {
          stdin.setRawMode(true);
        }
        stdin.resume();
        stdin.on("data", onStdinData);

        timer = setTimeout(() => {
          settle(reject, new ExpectTimeoutError(timeout, searchBuffer));
        }, timeout);
      } catch (error) {
        settle(reject, error);
      }
    });
  }

  #append(chunk) {
    this.#buffer += chunk;
    if (this.#buffer.length > this.#maxBuffer) {
      this.#buffer = this.#buffer.slice(-this.#maxBuffer);
    }
  }

  #assertOpen() {
    if (this.#closed) {
      throw new Error("PTY session is already closed");
    }
  }
}

export function spawn(command, args = [], options = {}) {
  return new TerminalSession(command, args, options);
}

export class ReconnectableSession extends EventEmitter {
  #create;
  #login;
  #session;
  #connecting;
  #reconnects = 0;

  constructor({ create, login }) {
    super();

    if (typeof create !== "function") {
      throw new TypeError("ReconnectableSession requires a create function");
    }

    if (typeof login !== "function") {
      throw new TypeError("ReconnectableSession requires a login function");
    }

    this.#create = create;
    this.#login = login;
  }

  get session() {
    return this.#session;
  }

  get reconnects() {
    return this.#reconnects;
  }

  async connect() {
    if (this.#connecting) {
      return this.#connecting;
    }

    this.#connecting = this.#connect();

    try {
      return await this.#connecting;
    } finally {
      this.#connecting = undefined;
    }
  }

  async reconnect(reason) {
    this.#session?.close();
    this.#session = undefined;
    this.#reconnects += 1;
    this.emit("reconnect", { reason, reconnects: this.#reconnects });
    return this.connect();
  }

  async withSession(work, options = {}) {
    const retries = options.retries ?? 1;
    let attempt = 0;

    while (true) {
      const session = await this.connect();

      try {
        return await work(session, {
          reconnects: this.#reconnects,
          attempt
        });
      } catch (error) {
        if (attempt >= retries || !isSessionClosure(error, session)) {
          throw error;
        }

        attempt += 1;
        await this.reconnect(error);
      }
    }
  }

  async close() {
    this.#session?.close();
    this.#session = undefined;
  }

  async #connect() {
    const session = this.#create();
    this.#session = session;

    session.once("exit", (event) => {
      this.emit("exit", event);
    });

    await this.#login(session);
    this.emit("connect", { reconnects: this.#reconnects });
    return session;
  }
}

export function reconnectable(options) {
  return new ReconnectableSession(options);
}

function isSessionClosure(error, session) {
  return error instanceof SessionClosedError || session.closed;
}

function findMatch(buffer, patterns) {
  for (let index = 0; index < patterns.length; index += 1) {
    const pattern = patterns[index];
    const match = matchPattern(buffer, pattern);

    if (match) {
      return {
        index,
        pattern,
        ...match
      };
    }
  }

  return undefined;
}

function matchPattern(buffer, pattern) {
  if (typeof pattern === "string") {
    const at = buffer.indexOf(pattern);
    if (at === -1) {
      return undefined;
    }
    return {
      text: pattern,
      at,
      groups: []
    };
  }

  if (pattern instanceof RegExp) {
    pattern.lastIndex = 0;
    const result = pattern.exec(buffer);
    if (!result) {
      return undefined;
    }
    return {
      text: result[0],
      at: result.index,
      groups: result.slice(1),
      match: result
    };
  }

  if (typeof pattern === "function") {
    const result = pattern(buffer);
    if (!result) {
      return undefined;
    }
    return {
      text: typeof result === "string" ? result : buffer,
      at: 0,
      value: result
    };
  }

  throw new TypeError(`Unsupported expect pattern: ${Object.prototype.toString.call(pattern)}`);
}

export function shell(options = {}) {
  const command = options.command ?? defaultShell();
  const args = options.args ?? [];
  return spawn(command, args, options);
}

function resolveCommand(command, env) {
  if (process.platform !== "win32" || /[\\/]/.test(command)) {
    return command;
  }

  const pathValue = env.Path ?? env.PATH ?? "";
  const extensions = command.includes(".")
    ? [""]
    : (env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD").split(";");

  for (const dir of pathValue.split(path.delimiter)) {
    if (!dir) {
      continue;
    }

    for (const extension of extensions) {
      const candidate = path.join(dir, `${command}${extension.toLowerCase()}`);
      if (fs.existsSync(candidate)) {
        return candidate;
      }

      const upperCandidate = path.join(dir, `${command}${extension.toUpperCase()}`);
      if (fs.existsSync(upperCandidate)) {
        return upperCandidate;
      }
    }
  }

  return command;
}

function defaultShell() {
  if (process.platform === "win32") {
    return process.env.ComSpec ?? "powershell.exe";
  }
  return process.env.SHELL ?? "/bin/sh";
}

export { os };
