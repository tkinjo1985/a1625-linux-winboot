#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('usb', 'wifi')]
    [string]$Transport = 'usb',

    [string]$Address,

    [string]$SshKeyPath,

    [string]$KnownHostsPath,

    [ValidateRange(3, 9)]
    [int]$Runs = 5,

    [ValidateRange(1, 30)]
    [int]$CpuSeconds = 3,

    [ValidateRange(8, 256)]
    [int]$MemoryArrayMiB = 32,

    [ValidateRange(8, 256)]
    [int]$CompressionMiB = 32,

    [switch]$SkipBuild,

    [switch]$SkipCompression,

    [ValidatePattern('^[A-Za-z0-9.-]+$')]
    [string]$IperfServerAddress,

    [ValidateRange(5, 120)]
    [int]$IperfSeconds = 15,

    [ValidateRange(0, 30)]
    [int]$CooldownSeconds = 2,

    [string]$OutputRoot,

    [ValidatePattern('^[A-Za-z0-9._-]{1,64}$')]
    [string]$Tag = 'default'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$stateModule = Join-Path $repoRoot 'windows-native\codex-state\A1625CodexState.psm1'
$benchSource = Join-Path $PSScriptRoot 'a1625-bench.c'
$buildSource = Join-Path $PSScriptRoot 'a1625-build-workload.c'

if (-not $SshKeyPath) {
    $SshKeyPath = Join-Path $repoRoot 'artifacts\ssh\a1625_ram_ed25519'
}
if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'artifacts\benchmark'
}

function Assert-File {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file was not found: $Path"
    }
}

function Resolve-KnownHosts {
    if (-not [string]::IsNullOrWhiteSpace($KnownHostsPath)) {
        Assert-File $KnownHostsPath
        return (Resolve-Path -LiteralPath $KnownHostsPath).ProviderPath
    }

    $stateRoot = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\state'
    $latest = Get-ChildItem -LiteralPath $stateRoot -Filter 'known_hosts_ram_*' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1

    if (-not $latest) {
        throw 'No per-boot known_hosts file was found. Run Restore-A1625RamEnvironment.ps1 first or pass -KnownHostsPath.'
    }
    return $latest.FullName
}

function Resolve-Address {
    if (-not [string]::IsNullOrWhiteSpace($Address)) {
        return $Address.Trim()
    }

    if ($Transport -eq 'usb') {
        return '172.16.42.1'
    }

    $saved = Join-Path $env:LOCALAPPDATA 'AppleTvA1625\wifi\last-address.txt'
    if (-not (Test-Path -LiteralPath $saved -PathType Leaf)) {
        throw "Wi-Fi transport was selected but no saved address exists: $saved"
    }
    $value = (Get-Content -LiteralPath $saved -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Saved Wi-Fi address is empty: $saved"
    }
    return $value
}

function Invoke-Remote {
    param(
        [Parameter(Mandatory)][string]$Command,
        [switch]$AllowFailure
    )

    # PowerShell here-strings use the host platform's line endings.  When this
    # script runs on Windows, a multiline command may therefore contain CRLF.
    # Passing that text unchanged to BusyBox /bin/sh makes lines such as
    # "set -eu\r" look like an invalid shell option.  Normalize every remote
    # command centrally before handing it to ssh.exe.
    $normalizedCommand = $Command -replace "`r`n", "`n" -replace "`r", "`n"
    $wrappedCommand = "export PATH=/opt/bin:/usr/bin:/bin:/usr/sbin:/sbin HOME=/run/codex-home LC_ALL=C; $normalizedCommand"
    $sshArguments = @($script:SshArguments)
    $raw = @(& ssh.exe @sshArguments "root@$script:TargetAddress" $wrappedCommand 2>&1)
    $code = $LASTEXITCODE
    $lines = @($raw | ForEach-Object { [string]$_ })

    if (-not $AllowFailure -and $code -ne 0) {
        throw "Remote command failed with exit code $code.`n$($lines -join "`n")"
    }

    [pscustomobject]@{
        ExitCode = $code
        Lines = $lines
    }
}

function Send-TextFile {
    param(
        [Parameter(Mandatory)][string]$LocalPath,
        [Parameter(Mandatory)][string]$RemotePath
    )

    $text = [IO.File]::ReadAllText($LocalPath, [Text.Encoding]::UTF8) -replace "`r`n", "`n"
    $bytes = [Text.Encoding]::UTF8.GetBytes($text)
    try {
        [void](Invoke-A1625SshUpload `
            -SshArguments $script:SshArguments `
            -AppleTvAddress $script:TargetAddress `
            -RemoteCommand "set -eu; umask 077; cat > '$RemotePath'; chmod 600 '$RemotePath'" `
            -Payload $bytes `
            -TimeoutSeconds 180)
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Parse-KvLine {
    param([Parameter(Mandatory)][string]$Line)

    $result = [ordered]@{}
    foreach ($part in $Line.Split(',')) {
        $pair = $part.Split('=', 2)
        if ($pair.Count -eq 2) {
            $result[$pair[0]] = $pair[1]
        }
    }
    return $result
}

function Get-MetricLine {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$Metric,
        [string]$Name
    )

    foreach ($line in $Lines) {
        if ($line -notmatch '^metric=') { continue }
        $kv = Parse-KvLine $line
        if ($kv['metric'] -ne $Metric) { continue }
        if ($Name -and $kv['name'] -ne $Name) { continue }
        return $kv
    }
    throw "Expected metric '$Metric' was not present in remote output.`n$($Lines -join "`n")"
}

function Add-Metric {
    param(
        [Parameter(Mandatory)][string]$Category,
        [Parameter(Mandatory)][string]$Metric,
        [Parameter(Mandatory)][int]$Run,
        [Parameter(Mandatory)][double]$Value,
        [Parameter(Mandatory)][string]$Unit,
        [string]$Note = ''
    )

    $script:Metrics.Add([pscustomobject]@{
        Category = $Category
        Metric = $Metric
        Run = $Run
        Value = $Value
        Unit = $Unit
        Note = $Note
    })
}

function Get-Stats {
    param([Parameter(Mandatory)][object[]]$Items)

    $values = @($Items | ForEach-Object { [double]$_.Value } | Sort-Object)
    $count = $values.Count
    if ($count -eq 0) { return $null }

    if ($count % 2 -eq 1) {
        $median = $values[[int][Math]::Floor($count / 2)]
    }
    else {
        $median = ($values[$count / 2 - 1] + $values[$count / 2]) / 2.0
    }

    [pscustomobject]@{
        Category = $Items[0].Category
        Metric = $Items[0].Metric
        Unit = $Items[0].Unit
        Runs = $count
        Median = $median
        Min = $values[0]
        Max = $values[-1]
    }
}

function Format-Number {
    param([double]$Value)
    if ([Math]::Abs($Value) -ge 1000000) {
        return $Value.ToString('N0', [Globalization.CultureInfo]::InvariantCulture)
    }
    return $Value.ToString('0.###', [Globalization.CultureInfo]::InvariantCulture)
}

Assert-File $stateModule
Assert-File $benchSource
Assert-File $buildSource
Assert-File $SshKeyPath

if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    throw 'ssh.exe was not found in PATH.'
}

Import-Module $stateModule -Force

$KnownHostsPath = Resolve-KnownHosts
$script:TargetAddress = Resolve-Address

$script:SshArguments = @('-F', 'none') + @(
    Get-A1625SshArguments -SshKeyPath $SshKeyPath -KnownHostsPath $KnownHostsPath
)

if ($Transport -eq 'wifi') {
    $script:SshArguments += @('-o', 'HostKeyAlias=172.16.42.1')
}

$timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmssZ')
$outputDirectory = Join-Path $OutputRoot "$timestamp-$Transport-$Tag"
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$remoteDir = '/run/a1625-benchmark'
$script:Metrics = [Collections.Generic.List[object]]::new()

Write-Host "A1625 benchmark target: root@$($script:TargetAddress) ($Transport)"
Write-Host "Runs per test: $Runs"
Write-Host "Output: $outputDirectory"

Write-Host "`n== Safety and toolchain preflight =="
$preflight = @'
set -eu
test "$(uname -m)" = "aarch64"
grep -q '^KernelPageSize:[[:space:]]*4 kB$' /proc/self/smaps
grep -q ' / rootfs ' /proc/mounts
awk 'NR > 1 && $1 ~ /^[0-9]+$/ && $4 !~ /^zram[0-9]+$/ { found=1 } END { exit found }' /proc/partitions
command -v gcc >/dev/null
command -v gzip >/dev/null
test -w /run
printf 'preflight=passed\n'
'@
$preflightResult = Invoke-Remote $preflight
if ('preflight=passed' -notin $preflightResult.Lines) {
    throw 'A1625 benchmark preflight did not produce the expected success marker.'
}

Write-Host "Preflight passed: aarch64, 4 KiB pages, RAM rootfs, no non-zram block device, gcc/gzip available."

Write-Host "`n== Stage benchmark sources into RAM =="
[void](Invoke-Remote "set -eu; rm -rf '$remoteDir'; umask 077; mkdir '$remoteDir'")
Send-TextFile -LocalPath $benchSource -RemotePath "$remoteDir/a1625-bench.c"
Send-TextFile -LocalPath $buildSource -RemotePath "$remoteDir/a1625-build-workload.c"

$benchSourceHash = (Get-FileHash -LiteralPath $benchSource -Algorithm SHA256).Hash.ToLowerInvariant()
$buildSourceHash = (Get-FileHash -LiteralPath $buildSource -Algorithm SHA256).Hash.ToLowerInvariant()
[void](Invoke-Remote "set -eu; echo '$benchSourceHash  $remoteDir/a1625-bench.c' | sha256sum -c -; echo '$buildSourceHash  $remoteDir/a1625-build-workload.c' | sha256sum -c -")

$compileCommand = "set -eu; cd '$remoteDir'; gcc -O2 -pipe -pthread -std=c11 a1625-bench.c -o a1625-bench; test -x a1625-bench"
[void](Invoke-Remote $compileCommand)

Write-Host "`n== Capture system information =="
$systemInfoCommand = @'
set -eu
echo "=== identity ==="
date -u '+utc=%Y-%m-%dT%H:%M:%SZ'
uname -a
printf 'arch='; uname -m
printf 'nproc='; (nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
printf 'uptime_seconds='; cut -d' ' -f1 /proc/uptime
echo
echo "=== kernel command line ==="
cat /proc/cmdline
echo
echo "=== development layer ==="
if test -s /run/a1625-development-layer.json; then cat /run/a1625-development-layer.json; else echo "not-present"; fi
echo
echo "=== cpuinfo ==="
cat /proc/cpuinfo
echo
echo "=== memory ==="
cat /proc/meminfo
echo
echo "=== swaps ==="
cat /proc/swaps
echo
echo "=== mounts ==="
cat /proc/mounts
echo
echo "=== load ==="
cat /proc/loadavg
echo
echo "=== cpufreq ==="
for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq \
         /sys/devices/system/cpu/cpu*/cpufreq/scaling_min_freq \
         /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq \
         /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    test -e "$f" || continue
    printf '%s=' "$f"
    cat "$f"
done
echo
echo "=== thermal ==="
for f in /sys/class/thermal/thermal_zone*/type /sys/class/thermal/thermal_zone*/temp; do
    test -e "$f" || continue
    printf '%s=' "$f"
    cat "$f"
done
'@
$systemInfo = Invoke-Remote $systemInfoCommand
$systemInfo.Lines | Set-Content -LiteralPath (Join-Path $outputDirectory 'system-info.txt') -Encoding utf8

$swapLines = @($systemInfo.Lines | Where-Object { $_ -match 'zram' })
if ($swapLines.Count -gt 0) {
    Write-Warning 'zram is enabled. Keep this result, but use a second run without -EnableZram for the cleanest CPU/memory baseline comparison.'
}

$nprocResult = Invoke-Remote "(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2) | head -1"
[int]$logicalCpus = ($nprocResult.Lines | Select-Object -First 1).Trim()
if ($logicalCpus -lt 1) { $logicalCpus = 1 }

Write-Host "Detected logical CPUs: $logicalCpus"

$compressionAvailable = -not $SkipCompression
if ($compressionAvailable) {
    $gzipProbe = Invoke-Remote "set -eu; printf x | gzip -1 -c >/dev/null; printf x | gzip -9 -c >/dev/null" -AllowFailure
    if ($gzipProbe.ExitCode -ne 0) {
        Write-Warning 'This gzip implementation does not accept the requested -1/-9 benchmark levels; compression tests will be skipped.'
        $compressionAvailable = $false
    }
}

$rawLogPath = Join-Path $outputDirectory 'raw-output.txt'
"Target=$($script:TargetAddress)`nTransport=$Transport`nRuns=$Runs`n" |
    Set-Content -LiteralPath $rawLogPath -Encoding utf8

for ($run = 1; $run -le $Runs; $run++) {
    Write-Host "`n== Run $run / $Runs =="

    $stateBefore = Invoke-Remote "printf 'uptime='; cut -d' ' -f1 /proc/uptime; printf 'load='; cat /proc/loadavg; printf 'mem_available_kib='; awk '/^MemAvailable:/ {print `$2}' /proc/meminfo"
    Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run state-before ---`n$($stateBefore.Lines -join "`n")"

    Write-Host 'CPU: single thread'
    $cpu1 = Invoke-Remote "cd '$remoteDir'; ./a1625-bench --cpu 1 $CpuSeconds"
    Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run cpu1 ---`n$($cpu1.Lines -join "`n")"
    $cpu1Metric = Get-MetricLine -Lines $cpu1.Lines -Metric 'cpu'
    Add-Metric -Category 'cpu' -Metric 'single_thread_ops_per_sec' -Run $run `
        -Value ([double]$cpu1Metric['ops_per_sec']) -Unit 'ops/s'

    Write-Host "CPU: $logicalCpus threads"
    $cpuAll = Invoke-Remote "cd '$remoteDir'; ./a1625-bench --cpu $logicalCpus $CpuSeconds"
    Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run cpu-all ---`n$($cpuAll.Lines -join "`n")"
    $cpuAllMetric = Get-MetricLine -Lines $cpuAll.Lines -Metric 'cpu'
    Add-Metric -Category 'cpu' -Metric 'all_thread_ops_per_sec' -Run $run `
        -Value ([double]$cpuAllMetric['ops_per_sec']) -Unit 'ops/s' -Note "threads=$logicalCpus"

    Write-Host "Memory: three arrays x $MemoryArrayMiB MiB"
    $memory = Invoke-Remote "cd '$remoteDir'; ./a1625-bench --memory $MemoryArrayMiB"
    Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run memory ---`n$($memory.Lines -join "`n")"
    foreach ($name in 'copy', 'scale', 'add', 'triad') {
        $m = Get-MetricLine -Lines $memory.Lines -Metric 'memory' -Name $name
        Add-Metric -Category 'memory' -Metric $name -Run $run `
            -Value ([double]$m['mib_per_sec']) -Unit 'MiB/s' -Note "array_mib=$MemoryArrayMiB"
    }

    if (-not $SkipBuild) {
        Write-Host 'Build: GCC -O2 compile+link workload'
        $build = Invoke-Remote "set -eu; cd '$remoteDir'; rm -f build-workload; ./a1625-bench --exec gcc -O2 -pipe a1625-build-workload.c -o build-workload; test -x build-workload; ./build-workload >/dev/null"
        Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run build ---`n$($build.Lines -join "`n")"
        $b = Get-MetricLine -Lines $build.Lines -Metric 'exec'
        Add-Metric -Category 'build' -Metric 'gcc_o2_compile_link_seconds' -Run $run `
            -Value ([double]$b['seconds']) -Unit 's'
    }

    if ($compressionAvailable) {
        if ($run -eq 1) {
            Write-Host "Compression input: generate $CompressionMiB MiB in RAM"
            $gen = Invoke-Remote "cd '$remoteDir'; ./a1625-bench --generate compress-input.bin $CompressionMiB"
            Add-Content -LiteralPath $rawLogPath -Value "`n--- compression-input ---`n$($gen.Lines -join "`n")"
        }

        foreach ($level in 1, 9) {
            Write-Host "Compression: gzip -$level"
            $compress = Invoke-Remote "set -eu; cd '$remoteDir'; rm -f compress-$level.gz; ./a1625-bench --exec sh -c 'gzip -$level -c compress-input.bin > compress-$level.gz'; test -s compress-$level.gz; printf 'compressed_bytes='; wc -c < compress-$level.gz"
            Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run gzip-$level ---`n$($compress.Lines -join "`n")"
            $c = Get-MetricLine -Lines $compress.Lines -Metric 'exec'
            $seconds = [double]$c['seconds']
            Add-Metric -Category 'compression' -Metric "gzip_${level}_mib_per_sec" -Run $run `
                -Value ($CompressionMiB / $seconds) -Unit 'MiB/s'
            Add-Metric -Category 'compression' -Metric "gzip_${level}_seconds" -Run $run `
                -Value $seconds -Unit 's'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($IperfServerAddress)) {
        Write-Host "Network: iperf3 -> $IperfServerAddress"
        $iperfCheck = Invoke-Remote "command -v iperf3 >/dev/null" -AllowFailure
        if ($iperfCheck.ExitCode -ne 0) {
            Write-Warning 'iperf3 is not installed on the A1625; network benchmark skipped.'
            $IperfServerAddress = $null
        }
        else {
            try {
                $forward = Invoke-Remote "iperf3 -c '$IperfServerAddress' -t $IperfSeconds -J"
                $forwardJson = ($forward.Lines -join "`n") | ConvertFrom-Json
                $forwardBps = [double]$forwardJson.end.sum_received.bits_per_second
                Add-Metric -Category 'network' -Metric 'send_mbit_per_sec' -Run $run `
                    -Value ($forwardBps / 1000000.0) -Unit 'Mbit/s' -Note "server=$IperfServerAddress"

                $reverse = Invoke-Remote "iperf3 -c '$IperfServerAddress' -t $IperfSeconds -R -J"
                $reverseJson = ($reverse.Lines -join "`n") | ConvertFrom-Json
                $reverseBps = [double]$reverseJson.end.sum_received.bits_per_second
                Add-Metric -Category 'network' -Metric 'receive_mbit_per_sec' -Run $run `
                    -Value ($reverseBps / 1000000.0) -Unit 'Mbit/s' -Note "server=$IperfServerAddress"

                Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run iperf-forward ---`n$($forward.Lines -join "`n")"
                Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run iperf-reverse ---`n$($reverse.Lines -join "`n")"
            }
            catch {
                Write-Warning "iperf3 run failed and will be omitted from the summary: $($_.Exception.Message)"
            }
        }
    }

    $stateAfter = Invoke-Remote "printf 'uptime='; cut -d' ' -f1 /proc/uptime; printf 'load='; cat /proc/loadavg; printf 'mem_available_kib='; awk '/^MemAvailable:/ {print `$2}' /proc/meminfo"
    Add-Content -LiteralPath $rawLogPath -Value "`n--- run=$run state-after ---`n$($stateAfter.Lines -join "`n")"

    if ($run -lt $Runs -and $CooldownSeconds -gt 0) {
        Write-Host "Cooldown: $CooldownSeconds s"
        Start-Sleep -Seconds $CooldownSeconds
    }
}

Write-Host "`n== Final system state =="
$finalState = Invoke-Remote $systemInfoCommand
$finalState.Lines | Set-Content -LiteralPath (Join-Path $outputDirectory 'system-info-after.txt') -Encoding utf8

$resultsCsv = Join-Path $outputDirectory 'results.csv'
$script:Metrics | Export-Csv -LiteralPath $resultsCsv -NoTypeInformation -Encoding utf8

$summary = @(
    $script:Metrics |
        Group-Object Category, Metric |
        ForEach-Object { Get-Stats -Items @($_.Group) } |
        Sort-Object Category, Metric
)

$compressionSetting = if ($compressionAvailable) { $CompressionMiB } else { $null }
$iperfSecondsSetting = if ($IperfServerAddress) { $IperfSeconds } else { $null }

$summaryObject = [ordered]@{
    schema = 'a1625-performance-v1'
    generatedUtc = [DateTime]::UtcNow.ToString('o')
    target = [ordered]@{
        address = $script:TargetAddress
        transport = $Transport
        tag = $Tag
        logicalCpus = $logicalCpus
    }
    configuration = [ordered]@{
        runs = $Runs
        cpuSeconds = $CpuSeconds
        memoryArrayMiB = $MemoryArrayMiB
        compressionMiB = $compressionSetting
        buildEnabled = -not $SkipBuild
        compressionEnabled = $compressionAvailable
        iperfServerAddress = $IperfServerAddress
        iperfSeconds = $iperfSecondsSetting
        cooldownSeconds = $CooldownSeconds
        benchmarkSourceSha256 = $benchSourceHash
        buildWorkloadSha256 = $buildSourceHash
        knownHostsPath = $KnownHostsPath
    }
    summary = $summary
}

$summaryObject | ConvertTo-Json -Depth 8 |
    Set-Content -LiteralPath (Join-Path $outputDirectory 'summary.json') -Encoding utf8

$report = [Collections.Generic.List[string]]::new()
$report.Add('# A1625 Linux performance report')
$report.Add('')
$report.Add("Generated UTC: $($summaryObject.generatedUtc)")
$report.Add('')
$report.Add("Transport: **$Transport**")
$report.Add('')
$report.Add("Target: ``$($script:TargetAddress)``")
$report.Add('')
$report.Add("Runs per metric: **$Runs**")
$report.Add('')
$report.Add("Logical CPUs: **$logicalCpus**")
$report.Add('')
if ($swapLines.Count -gt 0) {
    $report.Add('> zram was active during this run. For a clean CPU/memory baseline, compare against a run booted without `-EnableZram`.')
    $report.Add('')
}
$report.Add('## Summary')
$report.Add('')
$report.Add('| Category | Metric | Median | Min | Max | Unit |')
$report.Add('| --- | --- | ---: | ---: | ---: | --- |')
foreach ($item in $summary) {
    $report.Add("| $($item.Category) | $($item.Metric) | $(Format-Number $item.Median) | $(Format-Number $item.Min) | $(Format-Number $item.Max) | $($item.Unit) |")
}
$report.Add('')
$report.Add('## Interpretation')
$report.Add('')
$report.Add('- CPU values are a project-local deterministic integer workload. Use them for comparisons between A1625 kernel/configuration runs, not as a Geekbench/CoreMark equivalent.')
$report.Add('- Memory values are STREAM-style Copy/Scale/Add/Triad bandwidth using three RAM arrays.')
$report.Add('- Build time measures a fixed GCC `-O2` compile+link workload; lower is better.')
$report.Add('- gzip throughput measures deterministic RAM input and does not touch internal Apple TV storage.')
$report.Add('- iperf3 values are included only when `-IperfServerAddress` was supplied and iperf3 was available on the A1625.')
$report.Add('')
$report.Add('## Raw files')
$report.Add('')
$report.Add('- `system-info.txt` — state before benchmarking')
$report.Add('- `system-info-after.txt` — state after benchmarking')
$report.Add('- `results.csv` — every individual run')
$report.Add('- `summary.json` — machine-readable medians/min/max')
$report.Add('- `raw-output.txt` — raw benchmark output')
$report.Add('')
$report.Add('All benchmark scratch data on the A1625 was placed under `/run/a1625-benchmark`.')

$report | Set-Content -LiteralPath (Join-Path $outputDirectory 'report.md') -Encoding utf8

Write-Host "`nBenchmark complete." -ForegroundColor Green
Write-Host "Report: $(Join-Path $outputDirectory 'report.md')"
Write-Host "CSV:    $resultsCsv"
Write-Host "JSON:   $(Join-Path $outputDirectory 'summary.json')"

$summary | Format-Table Category, Metric, Median, Min, Max, Unit -AutoSize
