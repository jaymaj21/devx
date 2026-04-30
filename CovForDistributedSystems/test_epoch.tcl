#!/usr/bin/env tclsh
# Test epoch conversion

set file_start_ms 1762991121789

# Try dividing by 1000 to get seconds
set secs [expr {int($file_start_ms / 1000)}]
puts "file_start_ms: $file_start_ms"
puts "secs: $secs"
puts "Formatted: [clock format $secs -format {%Y-%m-%d %H:%M:%S} -gmt 1]"

# Let's also check what current epoch is
set now [clock seconds]
puts "\nCurrent epoch (seconds): $now"
puts "Current UTC: [clock format $now -format {%Y-%m-%d %H:%M:%S} -gmt 1]"

# The value seems very large. Let's try checking if it's actually in milliseconds or nanoseconds
set as_nanos [expr {$file_start_ms}]
set secs_from_nanos [expr {int($as_nanos / 1000000000)}]
puts "\nIf interpreted as nanoseconds:"
puts "secs: $secs_from_nanos"
if {$secs_from_nanos > 0} {
    puts "Formatted: [clock format $secs_from_nanos -format {%Y-%m-%d %H:%M:%S} -gmt 1]"
}
