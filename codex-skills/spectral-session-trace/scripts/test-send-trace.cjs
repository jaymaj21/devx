const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const vm = require('node:vm');
const { execFileSync } = require('node:child_process');
const { buildCommand, parseArgs } = require('./send-trace.cjs');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'spectral-trace-recorder-test-'));
const events = [
    { label: 'prompt', text: 'quotes " braces { } [set ::injected 1] $variable; \\ café 😀\nline\u0000end' },
    { label: 'command result', text: 'another\nentry' }
];
const encode = value => Buffer.from(value, 'utf8').toString('base64');
try {
    assert.equal(parseArgs(['--recorder', 'tcl', '--port', '32124', '--file', 'events.json']).recorder, 'tcl');
    assert.equal(parseArgs(['--port', '32123', '--file', 'events.json']).recorder, 'js');
    assert.throws(() => parseArgs(['--recorder', 'bad', '--port', '1', '--file', 'x']));
    assert.throws(() => buildCommand(events, 'bad'));
    assert.throws(() => buildCommand([{ label: 'x', text: 'a'.repeat(1000000) }], 'tcl'), /900 KiB/);
    const calls = [];
    const range = { cloneRange() { return this; } };
    const selection = { rangeCount: 1, getRangeAt() { return range; }, removeAllRanges() { calls.push('restore'); }, addRange(value) { assert.equal(value, range); } };
    const Spectral = { editor: {}, api: { savedEditorRange: range }, getPlainText: () => 'existing', inserText(index, text) { calls.push(text); }, createNote(index, text) { calls.push(text); return {}; } };
    assert.equal(vm.runInNewContext(buildCommand(events, 'js'), { window: { Spectral, getSelection: () => selection }, Spectral }), 'Trace appended: 2');
    assert(calls.includes(events[0].text));
    assert.equal(Spectral.api.savedEditorRange, range);
    fs.writeFileSync(path.join(directory, 'trace.tcl'), buildCommand(events, 'tcl'));
    // Extract and exercise the actual editor insertion procedures in an isolated Tk widget.
    const script = `
package require Tk
wm withdraw .
text .t
proc loadProc {source name} {
    set start [string first "proc $name " $source]
    if {$start < 0} {error "Missing $name"}
    set command ""
    foreach line [split [string range $source $start end] "\\n"] {
        append command $line "\\n"
        if {[info complete $command]} {uplevel #0 $command; return}
    }
    error "Incomplete procedure $name"
}
set file [open [lindex $argv 0] r]
set source [read $file]
close $file
loadProc $source insert_text
loadProc $source create_note
set folder [file dirname [info script]]
set spectral_subfolder notes
proc get_current_folder {} {return $::folder}
proc randString {} {return "note[incr ::noteNumber]"}
proc bind_note_button_context_menu {args} {}
set noteNumber 0
set modified 0
.t insert 1.0 existing
.t mark set insert 1.2
.t tag add sel 1.1 1.4
set saved [.t index insert]
set selected [.t tag ranges sel]
set file [open [file join $folder trace.tcl] r]
set command [read $file]
close $file
set result [eval $command]
if {$result ne "Trace appended: 2"} {error "Bad acknowledgment: $result"}
if {[.t index insert] ne $saved || [.t tag ranges sel] ne $selected} {error "Cursor/selection changed"}
if {[.t get 1.0 end-1c] ne "existing\\nprompt: \\ncommand result: \\n"} {error "Incorrect chronological layout: [.t get 1.0 end-1c]"}
if {$noteNumber != 2 || !$modified} {error "Missing notes or modified flag"}
set expected [list ${events.map(event => `[encoding convertfrom utf-8 [binary decode base64 {${encode(event.text)}}]]`).join(' ')}]
set index 0
foreach noteFile [lsort [glob [file join $folder notes *.txt]]] {
    set file [open $noteFile r]
    fconfigure $file -encoding utf-8
    set body [read $file]
    close $file
    if {$body ne [lindex $expected $index]} {error "Note text changed"}
    incr index
}
if {[info exists ::injected]} {error "Trace text executed as Tcl"}
rename create_note original_create_note
proc create_note {args} {error "simulated note failure"}
if {![catch {eval $command} failure] || $failure ne "simulated note failure"} {error "Expected failure"}
if {[.t index insert] ne $saved || [.t tag ranges sel] ne $selected} {error "Failure changed cursor/selection"}
rename create_note {}
rename original_create_note create_note
.t delete 1.0 end
eval $command
if {[.t get 1.0 end-1c] ne "prompt: \ncommand result: \n"} {error "Empty editor separator is wrong"}
.t delete 1.0 end
.t insert 1.0 "existing\n"
eval $command
if {[.t get 1.0 end-1c] ne "existing\nprompt: \ncommand result: \n"} {error "Existing newline was duplicated"}
puts "Tcl real insertion APIs, note files, literal serialization, layout and selection checks passed."
destroy .
exit
`;
    fs.writeFileSync(path.join(directory, 'test.tcl'), script);
    process.stdout.write(execFileSync(process.env.TCLSH || 'tclsh', [path.join(directory, 'test.tcl'), process.argv[2] || path.resolve(__dirname, '../../../development_tools/JMWrap/spectral_on_barebones.tk')], { encoding: 'utf8', timeout: 15000, windowsHide: true }));
    console.log('JS recorder regression and recorder argument/size checks passed.');
} finally {
    if (!path.resolve(directory).startsWith(path.resolve(os.tmpdir()) + path.sep)) throw new Error('Unexpected cleanup path');
    fs.rmSync(directory, { recursive: true, force: true });
}
