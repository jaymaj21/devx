param(
  [switch]$UpdateMarkdown
)

$ErrorActionPreference = 'Stop'

function Run-Java {
  Push-Location "fastest-speed-java"
  try {
    if ((Test-Path .\Main.java) -and (Test-Path .\mprewriter.java)) {
      javac Main.java mprewriter.java | Out-Null
    }
    $out = & java Main 2>&1 | Out-String
    return $out
  } finally {
    Pop-Location
  }
}

function Run-Cpp {
  Push-Location "CppAppWithUdpProbes"
  try {
    # Always rebuild to avoid stale/corrupted exe
    if (Test-Path .\latency_bench.exe) { Remove-Item -Force .\latency_bench.exe }
    g++ -O3 -std=c++17 -DMPREWRITER_STANDALONE=0 latency_bench.cpp mprewriter.cpp -lws2_32 -o latency_bench.exe | Out-Null
    $out = & .\latency_bench.exe 2>&1 | Out-String
    return $out
  } finally {
    Pop-Location
  }
}

function Run-Rust {
  Push-Location "RustAppWithUdpProbes/udp_probe_demo_v2"
  try {
    if (-not (Test-Path .\target\release\latency_bench.exe)) {
      cargo build --release --bin latency_bench | Out-Null
    }
    $out = & .\target\release\latency_bench.exe 2>&1 | Out-String
    return $out
  } finally {
    Pop-Location
  }
}

$javaOut = Run-Java
$cppOut  = Run-Cpp
$rustOut = Run-Rust

Write-Host $javaOut
Write-Host $cppOut
Write-Host $rustOut

if ($UpdateMarkdown) {
  $date = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

  $rxTotal  = 'Total time:\s*([0-9.]+)\s*ms'
  $rxAvg    = 'Average latency per hit:\s*([0-9.]+)\s*microseconds'

  $jAvg = [regex]::Match($javaOut, $rxAvg).Groups[1].Value
  $jTot = [regex]::Match($javaOut, $rxTotal).Groups[1].Value
  $cAvg = [regex]::Match($cppOut,  $rxAvg).Groups[1].Value
  $cTot = [regex]::Match($cppOut,  $rxTotal).Groups[1].Value
  $rAvg = [regex]::Match($rustOut, $rxAvg).Groups[1].Value
  $rTot = [regex]::Match($rustOut, $rxTotal).Groups[1].Value

  $md = @()
  $md += "---"
  $md += ""
  $md += "## Run $date"
  $md += ""
  $md += "### Summary Table (1M hits)"
  $md += ""
  $md += "| Language | Avg latency (µs) | Total time (ms) |"
  $md += "|----------|-------------------|-----------------|"
  $md += "| Java     | $jAvg             | $jTot           |"
  $md += "| C++      | $cAvg             | $cTot           |"
  $md += "| Rust     | $rAvg             | $rTot           |"
  $md += ""
  $md += "### Raw Outputs"
  $md += ""
  $md += "Java"
  $md += '```'
  $md += ($javaOut -replace '\r','').TrimEnd()
  $md += '```'
  $md += ""
  $md += "C++"
  $md += '```'
  $md += ($cppOut -replace '\r','').TrimEnd()
  $md += '```'
  $md += ""
  $md += "Rust"
  $md += '```'
  $md += ($rustOut -replace '\r','').TrimEnd()
  $md += '```'

  Add-Content -Path "benchmark.md" -Value ($md -join "`r`n")
}

