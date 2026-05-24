param(
    [int]$ThreadCount = 4,
    [int]$Iterations = 24
)

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"
Set-StrictMode -Version Latest

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Invoke-Maven {
    param(
        [string]$WorkingDirectory,
        [string[]]$Arguments
    )

    Push-Location $WorkingDirectory
    try {
        & mvn @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Maven failed in $WorkingDirectory"
        }
    }
    finally {
        Pop-Location
    }
}

function Resolve-RequiredFile {
    param(
        [string]$Path,
        [string]$Label
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function Start-CaptureProcess {
    param(
        [string]$FileName,
        [string[]]$Arguments,
        [string]$WorkingDirectory,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FileName
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $quotedArgs = foreach ($arg in $Arguments) {
        if ($arg -match '[\s"]') {
            '"' + ($arg -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
        } else {
            $arg
        }
    }
    $psi.Arguments = ($quotedArgs -join " ")

    $stdoutWriter = [System.IO.StreamWriter]::new($StdoutPath, $false, [System.Text.Encoding]::UTF8)
    $stderrWriter = [System.IO.StreamWriter]::new($StderrPath, $false, [System.Text.Encoding]::UTF8)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    $process.EnableRaisingEvents = $true

    $outRegistration = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
        if ($EventArgs.Data -ne $null) {
            $Event.MessageData.Out.WriteLine($EventArgs.Data)
            $Event.MessageData.Out.Flush()
        }
    } -MessageData @{ Out = $stdoutWriter }

    $errRegistration = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data -ne $null) {
            $Event.MessageData.Err.WriteLine($EventArgs.Data)
            $Event.MessageData.Err.Flush()
        }
    } -MessageData @{ Err = $stderrWriter }

    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    return @{
        Process = $process
        StdoutWriter = $stdoutWriter
        StderrWriter = $stderrWriter
        OutputRegistration = $outRegistration
        ErrorRegistration = $errRegistration
    }
}

function Stop-CaptureProcess {
    param($Capture)

    try {
        if (-not $Capture.Process.HasExited) {
            $Capture.Process.WaitForExit()
        }
    }
    finally {
        Unregister-Event -SourceIdentifier $Capture.OutputRegistration.Name -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier $Capture.ErrorRegistration.Name -ErrorAction SilentlyContinue
        Remove-Job -Id $Capture.OutputRegistration.Id -Force -ErrorAction SilentlyContinue
        Remove-Job -Id $Capture.ErrorRegistration.Id -Force -ErrorAction SilentlyContinue
        $Capture.StdoutWriter.Dispose()
        $Capture.StderrWriter.Dispose()
        $Capture.Process.Dispose()
    }
}

function Wait-ForServerReady {
    param(
        [string]$StdoutPath,
        [int]$TimeoutSeconds = 20
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $StdoutPath) {
            $text = Get-Content -LiteralPath $StdoutPath -Raw
            if ($text -match "\[UDP\] Listening on port 8083" -and $text -match "\[TCP\] Listening on port 8084") {
                return
            }
        }
        Start-Sleep -Milliseconds 250
    }

    throw "Timed out waiting for code-analytics to start"
}

function Assert-MatchCount {
    param(
        [string]$Text,
        [string]$Pattern,
        [int]$Expected,
        [string]$Label
    )

    $count = ([regex]::Matches($Text, $Pattern)).Count
    if ($count -ne $Expected) {
        throw "$Label count mismatch. Expected $Expected, found $count"
    }
}

$repoRoot = $PSScriptRoot
$codeAnalyticsDir = Join-Path $repoRoot "code-analytics"
$runtimeDir = Join-Path $repoRoot "branch-probe-suite\mprewriter-runtime"
$artifactsDir = Join-Path $repoRoot "artifacts\mprewriter-runtime-race-test"
Ensure-Directory $artifactsDir
$runDir = Join-Path $artifactsDir (Get-Date -Format "yyyyMMdd-HHmmss")
Ensure-Directory $runDir

$serverStdout = Join-Path $runDir "code-analytics-stdout.txt"
$serverStderr = Join-Path $runDir "code-analytics-stderr.txt"
$clientStdout = Join-Path $runDir "client-stdout.txt"
$clientStderr = Join-Path $runDir "client-stderr.txt"
$traceSummary = Join-Path $runDir "trace-summary.txt"
$traceTool = Join-Path $repoRoot "plant_trace_tool.tcl"

$expectedPerKind = $ThreadCount * $Iterations
$expectedLogs = $expectedPerKind + 1

$serverJar = Join-Path $codeAnalyticsDir "target\clojure-shell-1.0-SNAPSHOT-jar-with-dependencies.jar"
$runtimeJar = Join-Path $runtimeDir "target\mprewriter-runtime-1.0.0.jar"
$runtimeClasses = Join-Path $runtimeDir "target\classes"
$testClasses = Join-Path $runtimeDir "target\test-classes"
$runtimeSource = Join-Path $runtimeDir "src\main\java\com\trading\domain\mprewriter.java"
$testSource = Join-Path $runtimeDir "src\test\java\com\trading\domain\MprewriterRuntimeMixedTrafficApp.java"

if (-not (Test-Path -LiteralPath $serverJar -PathType Leaf)) {
    Invoke-Maven -WorkingDirectory $codeAnalyticsDir -Arguments @("-DskipTests", "package")
}
if (-not (Test-Path -LiteralPath $runtimeJar -PathType Leaf)) {
    Invoke-Maven -WorkingDirectory $runtimeDir -Arguments @("-DskipTests", "package")
}

Ensure-Directory $runtimeClasses
Ensure-Directory $testClasses
& javac -d $runtimeClasses $runtimeSource
if ($LASTEXITCODE -ne 0) {
    throw "javac failed for mprewriter runtime"
}
& javac -cp $runtimeClasses -d $testClasses $testSource
if ($LASTEXITCODE -ne 0) {
    throw "javac failed for mixed traffic test client"
}

$serverJar = Resolve-RequiredFile -Path $serverJar -Label "Code analytics server jar"
$runtimeClasses = Resolve-Path -LiteralPath $runtimeClasses | Select-Object -ExpandProperty Path
$traceTool = Resolve-RequiredFile -Path $traceTool -Label "Trace tool"

$existingTraceNames = @{}
Get-ChildItem -Path (Join-Path $codeAnalyticsDir "plant-trace-*.txt") -File -ErrorAction SilentlyContinue | ForEach-Object {
    $existingTraceNames[$_.Name] = $true
}

$serverCapture = Start-CaptureProcess -FileName "java" `
    -Arguments @("-cp", $serverJar, "com.codeanalytics.ClojureShell") `
    -WorkingDirectory $codeAnalyticsDir `
    -StdoutPath $serverStdout `
    -StderrPath $serverStderr

try {
    Wait-ForServerReady -StdoutPath $serverStdout
    Start-Sleep -Milliseconds 500

    $clientClassPath = [string]::Join(";", @($runtimeClasses, $testClasses))
    $clientOutput = & java `
        "-cp" $clientClassPath `
        "-Dmprewriter.host=127.0.0.1" `
        "-Dmprewriter.port=8083" `
        "-Dmprewriter.appId=701" `
        "-Dmprewriter.instanceId=17" `
        "com.trading.domain.MprewriterRuntimeMixedTrafficApp" `
        $ThreadCount `
        $Iterations 2>&1
    $clientOutput | Set-Content -LiteralPath $clientStdout
    if ($LASTEXITCODE -ne 0) {
        throw "Mixed traffic client failed"
    }

    Start-Sleep -Seconds 2
    $null = $serverCapture.Process.StandardInput.WriteLine(":flush-trace")
    $null = $serverCapture.Process.StandardInput.WriteLine(":trace-persist")
    $null = $serverCapture.Process.StandardInput.WriteLine(":exit")
    $serverCapture.Process.StandardInput.Close()
    $serverCapture.Process.WaitForExit()
}
finally {
    Stop-CaptureProcess -Capture $serverCapture
}

$serverText = Get-Content -LiteralPath $serverStdout -Raw
$serverErr = if (Test-Path -LiteralPath $serverStderr) { Get-Content -LiteralPath $serverStderr -Raw } else { "" }

$newTrace = Get-ChildItem -Path (Join-Path $codeAnalyticsDir "plant-trace-*.txt") -File |
    Where-Object { -not $existingTraceNames.ContainsKey($_.Name) } |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1
if (-not $newTrace) {
    $newTrace = Get-ChildItem -Path (Join-Path $codeAnalyticsDir "plant-trace-*.txt") -File |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}
if (-not $newTrace) {
    throw "No saved trace was produced by code-analytics"
}

$savedTrace = Join-Path $runDir $newTrace.Name
Copy-Item -LiteralPath $newTrace.FullName -Destination $savedTrace -Force

$summaryOutput = & tclsh $traceTool summary $savedTrace 2>&1
$summaryOutput | Set-Content -LiteralPath $traceSummary
if ($LASTEXITCODE -ne 0) {
    throw "Trace summary failed"
}

$summaryText = Get-Content -LiteralPath $traceSummary -Raw
Assert-MatchCount -Text $summaryText -Pattern "LOG messages: $expectedLogs" -Expected 1 -Label "Summary log count"
Assert-MatchCount -Text $summaryText -Pattern "CTX attach messages: $expectedPerKind" -Expected 1 -Label "Summary attach count"
Assert-MatchCount -Text $summaryText -Pattern "CTX withdraw messages: $expectedPerKind" -Expected 1 -Label "Summary withdraw count"
Assert-MatchCount -Text $summaryText -Pattern "HIT messages: $expectedPerKind" -Expected 1 -Label "Summary hit count"

if ($serverText -match "Exception" -or $serverErr -match "Exception") {
    throw "Server reported an exception during the mixed traffic run"
}

Write-Host "Race test passed"
Write-Host "Run directory: $runDir"
Write-Host "Saved trace: $savedTrace"
Write-Host "Expected worker logs: $expectedPerKind"
Write-Host "Expected context apply/withdraw pairs: $expectedPerKind"
Write-Host "Expected total logs: $expectedLogs"
