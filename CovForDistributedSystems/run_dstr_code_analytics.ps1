param(
    [string]$DstrRoot = "C:\Git\jmtools\dstr",
    [string]$SpecPath = "test-suite\specs\mutex-2proc.json",
    [int]$StartId = 10001,
    [int]$AppId = 410,
    [int]$InstanceId = 1,
    [string]$OutputRoot = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Resolve-ExistingFile {
    param([string]$Path, [string]$Label)
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
        throw "$Label was not found: $Path"
    }
    return $resolved.Path
}

function Select-Artifact {
    param(
        [string]$Pattern,
        [string[]]$ExcludePatterns = @("*-sources.jar", "*-javadoc.jar", "*-tests.jar", "*-original.jar")
    )

    $items = Get-ChildItem -Path $Pattern -File -ErrorAction Stop |
        Where-Object {
            $name = $_.Name
            -not ($ExcludePatterns | Where-Object { $name -like $_ })
        } |
        Sort-Object LastWriteTimeUtc -Descending

    if (-not $items) {
        throw "No artifact matched pattern: $Pattern"
    }

    return $items[0].FullName
}

function Invoke-Maven {
    param(
        [string]$WorkingDirectory,
        [string[]]$Arguments
    )

    Write-Host "Running Maven in $WorkingDirectory"
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

function Invoke-Java {
    param(
        [string[]]$Arguments,
        [string]$WorkingDirectory = ""
    )

    if ($WorkingDirectory) {
        Push-Location $WorkingDirectory
    }

    try {
        & java @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Java command failed: $($Arguments -join ' ')"
        }
    }
    finally {
        if ($WorkingDirectory) {
            Pop-Location
        }
    }
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
        }
        else {
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

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $PSScriptRoot "artifacts\dstr-trace"
}

$repoRoot = $PSScriptRoot
$codeAnalyticsDir = Join-Path $repoRoot "code-analytics"
$instrumenterDir = Join-Path $repoRoot "branch-probe-instrumenter"
$runtimeDir = Join-Path $repoRoot "branch-probe-suite\mprewriter-runtime"
$traceTool = Resolve-ExistingFile -Path (Join-Path $repoRoot "plant_trace_tool.tcl") -Label "Trace tool"

Ensure-Directory $OutputRoot
$runStamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runDir = Join-Path $OutputRoot $runStamp
Ensure-Directory $runDir

$serverJarPattern = Join-Path $codeAnalyticsDir "target\clojure-shell-*-jar-with-dependencies.jar"
$instrumenterJarPattern = Join-Path $instrumenterDir "target\branch-probe-instrumenter-*-jar-with-dependencies.jar"
$runtimeJarPattern = Join-Path $runtimeDir "target\mprewriter-runtime-*.jar"

Invoke-Maven -WorkingDirectory $codeAnalyticsDir -Arguments @("-DskipTests", "package")
Invoke-Maven -WorkingDirectory $instrumenterDir -Arguments @("-DskipTests", "clean", "package")
if (-not (Get-ChildItem -Path $runtimeJarPattern -File -ErrorAction SilentlyContinue)) {
    Invoke-Maven -WorkingDirectory $runtimeDir -Arguments @("-DskipTests", "package")
}

Invoke-Maven -WorkingDirectory $DstrRoot -Arguments @("-DskipTests", "package", "dependency:copy-dependencies", "-DincludeScope=runtime")

$serverJar = Select-Artifact -Pattern $serverJarPattern
$instrumenterJar = Select-Artifact -Pattern $instrumenterJarPattern
$runtimeJar = Select-Artifact -Pattern $runtimeJarPattern
$dstrJar = Select-Artifact -Pattern (Join-Path $DstrRoot "target\dstr-*.jar")

$resolvedSpec = $SpecPath
if (-not [System.IO.Path]::IsPathRooted($resolvedSpec)) {
    $resolvedSpec = Join-Path $DstrRoot $resolvedSpec
}
$resolvedSpec = Resolve-ExistingFile -Path $resolvedSpec -Label "Spec file"

$dependencyDir = Join-Path $DstrRoot "target\dependency"
$dependencyJars = @(Get-ChildItem -Path (Join-Path $dependencyDir "*.jar") -File -ErrorAction Stop | ForEach-Object { $_.FullName })
if (-not $dependencyJars) {
    throw "No runtime dependency jars were copied into $dependencyDir"
}

$instrumentedJar = Join-Path $runDir "dstr-instrumented.jar"
$branchProbeCsv = Join-Path $runDir "dstr-instrumented-branch-probes.csv"
$dstrOutput = Join-Path $runDir "dstr-output.txt"
$serverStdout = Join-Path $runDir "code-analytics-stdout.txt"
$serverStderr = Join-Path $runDir "code-analytics-stderr.txt"
$summaryPath = Join-Path $runDir "trace-summary.txt"
$manifestPath = Join-Path $runDir "run-manifest.txt"

Write-Host "Instrumenting $dstrJar"
Invoke-Java -Arguments @("-jar", $instrumenterJar, "--startid=$StartId", "--sidecar", $dstrJar, $instrumentedJar)

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
    Start-Sleep -Milliseconds 750

    $classPath = [string]::Join(";", @($runtimeJar, $instrumentedJar) + $dependencyJars)
    $javaArgs = @(
        "-cp", $classPath,
        "-Dmprewriter.host=127.0.0.1",
        "-Dmprewriter.port=8083",
        "-Dmprewriter.appId=$AppId",
        "-Dmprewriter.instanceId=$InstanceId",
        "org.dstr.cli.DstrCli",
        $resolvedSpec
    )

    Write-Host "Running instrumented dstr against $resolvedSpec"
    $appOutput = & java @javaArgs 2>&1
    $appOutput | Set-Content -LiteralPath $dstrOutput
    if ($LASTEXITCODE -ne 0) {
        throw "Instrumented dstr run failed"
    }

    Start-Sleep -Seconds 1
    $null = $serverCapture.Process.StandardInput.WriteLine(":flush-trace")
    $null = $serverCapture.Process.StandardInput.WriteLine(":trace-persist")
    $null = $serverCapture.Process.StandardInput.WriteLine(":hits")
    $null = $serverCapture.Process.StandardInput.WriteLine(":exit")
    $serverCapture.Process.StandardInput.Close()

    $serverCapture.Process.WaitForExit()
}
finally {
    Stop-CaptureProcess -Capture $serverCapture
}

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
    throw "No saved plant trace was found after the run"
}

$savedTrace = Join-Path $runDir $newTrace.Name
Copy-Item -LiteralPath $newTrace.FullName -Destination $savedTrace -Force

$summaryOutput = & tclsh $traceTool summary $savedTrace 2>&1
$summaryOutput | Set-Content -LiteralPath $summaryPath
if ($LASTEXITCODE -ne 0) {
    throw "Trace summary failed"
}

@(
    "Run directory: $runDir"
    "Spec: $resolvedSpec"
    "Dstr jar: $dstrJar"
    "Instrumented jar: $instrumentedJar"
    "Branch probes: $branchProbeCsv"
    "Saved trace: $savedTrace"
    "Dstr output: $dstrOutput"
    "Code Analytics stdout: $serverStdout"
    "Code Analytics stderr: $serverStderr"
    "Trace summary: $summaryPath"
) | Set-Content -LiteralPath $manifestPath

Write-Host ""
Write-Host "Saved trace: $savedTrace"
Write-Host "Summary:"
Get-Content -LiteralPath $summaryPath
