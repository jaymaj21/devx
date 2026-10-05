# Spectral Tcl command server

In Spectral's Quick Command bar, run:

```tcl
startCmdServer 32124
```

The listener binds only to `127.0.0.1`. Nothing starts automatically.
Scripts execute in the main editor interpreter, with access to `.t`, editor
procedures, and global variables. The returned Tcl value becomes the reply;
`puts` still writes to the editor process's standard output.

From a terminal in JMWrap:

```powershell
tclsh cmd_client.tcl 32124 -c 'expr {6 * 7}'
tclsh cmd_client.tcl 32124 -c '.t insert end "Hello from TCP\n"'
tclsh cmd_client.tcl 32124 -f commands.tcl
```

The existing JavaScript client also works unchanged:

```powershell
node cmd_client.js 32124 -c 'expr {6 * 7}'
node cmd_client.js 32124 -f commands.tcl
```

Stop the listener and its connections from Quick Command:

```tcl
stopCmdServer 32124
```

Use different ports for the Tcl editor and the VS Code editor when both are
running. Starting a duplicate listener or stopping a missing listener reports
an error. Closing the editor process also closes its sockets.

## Protocol and client API

Each command is UTF-8 text followed by a literal NUL byte. Replies are UTF-8
`Result: <value>` or `Error: <message>`, followed by NUL. Connections can carry
multiple commands; commands run in order on each connection. Requests larger
than 1 MiB are rejected and that connection is closed. NUL in a result is
escaped as `\0` so it cannot terminate a reply prematurely.

Both clients reject commands containing NUL. The Tcl client waits up to 30
seconds, exits 0 for success, 1 for a server/transport error, and 2 for invalid
arguments. `--help` lists its command-line options. A client timeout does not
cancel an already-running script. Long-running Tcl code runs on the editor's
event loop and can block the UI, just like a locally evaluated script.

The client can also be sourced without executing its CLI:

```tcl
source cmd_client.tcl
set reply [::spectral_cmd_client::sendCommand 32124 {expr {6 * 7}}]
# Optional timeout in milliseconds:
set reply [::spectral_cmd_client::sendCommand 32124 {expr {6 * 7}} 5000]
```

`spectral_cmd_server.tcl` is sourced by `spectral_on_barebones.tk` and must
remain beside it. It can also be sourced from plain `tclsh` for headless use;
keep the event loop running with `vwait` after starting a listener. Tcl 8.6 is
required for the client.

## Verification

From JMWrap, run `node test_cmd_server.cjs`. Set `TCLSH` to a Tcl executable
path if `tclsh` is not on PATH. Tests cover Tcl and JavaScript clients,
UTF-8 (including emoji), fragmented and multiple messages, global state,
errors, empty commands, large requests/replies, listener lifecycle, and
client timeout/disconnect behavior. The tests run headlessly; they do not
launch the full Tk editor.
