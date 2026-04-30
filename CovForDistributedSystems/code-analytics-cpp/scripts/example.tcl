# Demo script for the REPL. Run with:
#   ./cov_server --run scripts/example.tcl
puts "Context before any messages:"
puts [ctx current]
puts "Known contexts:"
puts [ctx list]
puts "Hits (first 10):"
puts [hits 10]
