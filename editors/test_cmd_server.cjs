'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const net = require('node:net');
const { spawn, execFile } = require('node:child_process');
const { promisify } = require('node:util');
const run = promisify(execFile);
const { sendCommand } = require('../SpectralHtmlEditor/Spectralweb_vscode/cmd_client.js');
const tclsh = process.env.TCLSH || 'tclsh';
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'spectral-tcl-server-'));
let server;
let checks = 0;
function check(actual, expected) { assert.equal(actual, expected); checks++; console.log(`ok - check ${checks}`); }
async function startServer() {
    const harness = path.join(directory, 'server.tcl');
    fs.writeFileSync(harness, `
source [lindex $argv 0]
set editorFile [open [lindex $argv 1] r]
set editorSource [read $editorFile]
close $editorFile
if {![info complete $editorSource]} {error "Editor Tcl source is incomplete"}
foreach port {0 -1 65536 abc} {
    if {![catch {startCmdServer $port}]} {error "Invalid port accepted"}
}
set probe [socket -server {} -myaddr 127.0.0.1 0]
set port [lindex [fconfigure $probe -sockname] end]
close $probe
startCmdServer $port
if {![catch {startCmdServer $port}]} {error "Duplicate port accepted"}
puts "READY $port"
flush stdout
vwait forever
`, 'utf8');
    server = spawn(tclsh, [harness, path.join(__dirname, 'spectral_cmd_server.tcl'), path.join(__dirname, 'spectral_on_barebones.tk')], { windowsHide: true });
    return new Promise((resolve, reject) => {
        let output = '';
        let errors = '';
        const timer = setTimeout(() => reject(new Error('Server startup timed out: ' + errors)), 10000);
        server.stderr.on('data', chunk => { errors += chunk; });
        server.on('error', reject);
        server.on('exit', code => { clearTimeout(timer); reject(new Error(`Server exited ${code}: ${errors}`)); });
        server.stdout.on('data', chunk => {
            output += chunk;
            const match = output.match(/READY (\d+)/);
            if (match) { clearTimeout(timer); resolve(Number(match[1])); }
        });
    });
}
function exchange(port, chunks, count = 1) {
    return new Promise((resolve, reject) => {
        const socket = net.createConnection({ host: '127.0.0.1', port });
        let buffer = Buffer.alloc(0);
        const replies = [];
        socket.setTimeout(5000);
        socket.on('error', reject);
        socket.on('timeout', () => { socket.destroy(); reject(new Error('Protocol test timeout')); });
        socket.on('connect', async () => {
            for (const chunk of chunks) {
                socket.write(chunk);
                await new Promise(resolve => setTimeout(resolve, 10));
            }
        });
        socket.on('data', chunk => {
            buffer = Buffer.concat([buffer, chunk]);
            let index;
            while ((index = buffer.indexOf(0)) >= 0) {
                replies.push(buffer.subarray(0, index).toString('utf8'));
                buffer = buffer.subarray(index + 1);
            }
            if (replies.length >= count) { socket.destroy(); resolve(replies); }
        });
    });
}
async function tclClient(port, mode, value) {
    return run(tclsh, [path.join(__dirname, 'cmd_client.tcl'), String(port), mode, value], { encoding: 'utf8', timeout: 10000, windowsHide: true });
}
async function main() {
    const port = await startServer();
    const send = command => sendCommand({ port, command, timeoutMs: 5000 });
    check(await send('expr {6 * 7}'), 'Result: 42');
    check(await send('return {returned value}'), 'Result: returned value');
    check(await send('set ::shared 19'), 'Result: 19');
    check(await send('incr ::shared'), 'Result: 20');
    check(await send('error {deliberate failure}'), 'Error: deliberate failure');
    check(await send('  '), 'Error: empty command');
    check(await send('set x "unterminated'), 'Error: missing "');
    check(await send('set unicode {café Ελληνικά 😀}'), 'Result: café Ελληνικά 😀');
    check(await send('set value "a\\x00b"'), 'Result: a\\0b');
    const framed = Buffer.from('set unicode {café 😀}\0', 'utf8');
    check((await exchange(port, [framed.subarray(0, 17), framed.subarray(17, 21), framed.subarray(21)]))[0], 'Result: café 😀');
    check((await exchange(port, [Buffer.from('expr {1+1}\0expr {2+2}\0')], 2)).join('|'), 'Result: 2|Result: 4');
    check((await exchange(port, [Buffer.from('update; expr {3+3}\0expr {4+4}\0')], 2)).join('|'), 'Result: 6|Result: 8');
    check(await send('string repeat x 200000'), 'Result: ' + 'x'.repeat(200000));
    check((await exchange(port, [Buffer.alloc(1048577, 120)]))[0], 'Error: command exceeds 1 MiB');
    check(await send('expr {5+5}'), 'Result: 10');
    check((await tclClient(port, '-c', 'expr {7 * 8}')).stdout.trim(), 'Result: 56');
    const scriptFile = path.join(directory, 'command.tcl');
    fs.writeFileSync(scriptFile, 'set text {café 😀}\nset text', 'utf8');
    check((await tclClient(port, '-f', scriptFile)).stdout.trim(), 'Result: café 😀');
    await assert.rejects(tclClient(port, '-c', 'error {client failure}'), error => error.code === 1 && error.stdout.trim() === 'Error: client failure'); checks++;
    fs.writeFileSync(scriptFile, 'set x "a\0b"');
    await assert.rejects(tclClient(port, '-f', scriptFile), error => error.code === 1 && /contains a NUL byte/.test(error.stderr)); checks++;
    // A JavaScript peer verifies the Tcl client uses the same framing both ways.
    const peer = net.createServer(socket => {
        let buffer = Buffer.alloc(0);
        socket.on('data', chunk => {
            buffer = Buffer.concat([buffer, chunk]);
            const index = buffer.indexOf(0);
            if (index >= 0) {
                check(buffer.subarray(0, index).toString('utf8'), 'café 😀');
                socket.end(Buffer.from('Result: café 😀\0', 'utf8'));
            }
        });
    });
    await new Promise(resolve => peer.listen(0, '127.0.0.1', resolve));
    try { check((await tclClient(peer.address().port, '-c', 'café 😀')).stdout.trim(), 'Result: café 😀'); }
    finally { await new Promise(resolve => peer.close(resolve)); }
    // Client timeout and premature disconnect paths.
    const timeoutScript = path.join(directory, 'timeout.tcl');
    fs.writeFileSync(timeoutScript, `source [lindex $argv 0]\nif {![catch {::spectral_cmd_client::sendCommand [lindex $argv 1] {expr 1} 100} result]} {error "Expected timeout"}\nputs $result\n`);
    const silent = net.createServer(socket => socket.on('data', () => {}));
    await new Promise(resolve => silent.listen(0, '127.0.0.1', resolve));
    try {
        const result = await run(tclsh, [timeoutScript, path.join(__dirname, 'cmd_client.tcl'), String(silent.address().port)], { timeout: 10000, windowsHide: true });
        check(result.stdout.trim(), 'Timed out after 100 ms waiting for a response.');
    } finally { await new Promise(resolve => silent.close(resolve)); }
    const early = net.createServer(socket => { socket.resume(); socket.end('Result: incomplete'); });
    await new Promise(resolve => early.listen(0, '127.0.0.1', resolve));
    try { await assert.rejects(tclClient(early.address().port, '-c', 'expr 1'), error => /before a NUL-terminated/.test(error.stderr)); checks++; console.log(`ok - check ${checks}`); }
    finally { await new Promise(resolve => early.close(resolve)); }
    check(await send('set probe [socket -server {} -myaddr 127.0.0.1 0]; set other [lindex [fconfigure $probe -sockname] end]; close $probe; startCmdServer $other; stopCmdServer $other; catch {stopCmdServer $other}'), 'Result: 1');
    console.log(`${checks} command-server/client checks passed.`);
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
    if (server) server.kill();
    if (!path.resolve(directory).startsWith(path.resolve(os.tmpdir()) + path.sep)) throw new Error('Unexpected test cleanup path');
    fs.rmSync(directory, { recursive: true, force: true });
});
