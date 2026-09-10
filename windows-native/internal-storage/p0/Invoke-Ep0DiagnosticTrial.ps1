param(
    [Parameter(Mandatory=$true)][string]$IdentityPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$ApprovedPayloadSha256
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $out.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must stay inside repository'}
if(Test-Path -LiteralPath $out){throw 'Output directory exists; no automatic repeat'}
$manifest=Get-Content (Join-Path $PSScriptRoot 'build-manifest.json') -Raw|ConvertFrom-Json
if($ApprovedPayloadSha256 -ne $manifest.m1n1_bin_sha256){throw 'Approved payload hash mismatch'}
$identityFull=(Resolve-Path -LiteralPath $IdentityPath).Path
$armScript=(Resolve-Path (Join-Path $PSScriptRoot 'Invoke-Ep0TraceRead.ps1')).Path
$probe=(Resolve-Path (Join-Path $PSScriptRoot 'trace_open.py')).Path
$python='C:\Users\tkinj\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$deps=(Resolve-Path (Join-Path $root 'artifacts/ans-p0-python-deps')).Path
$powershell=(Get-Command powershell.exe).Source
New-Item -ItemType Directory -Path $out|Out-Null
$record=[ordered]@{mode='P0-USB armed one-shot EP0 diagnostic';status='starting';
    arm_attempts=0;com_open_attempts=0;report_attempts=0;proxy_requests=0;
    nop_requests=0;ans_requests=0;nand_requests=0;approved_payload_sha256=$ApprovedPayloadSha256;
    timeline=@();hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath,$armScript,$probe,$identityFull,(Join-Path $PSScriptRoot 'build-manifest.json')|Select Path,Hash)}
$recordPath=Join-Path $out 'session.json';$record|ConvertTo-Json -Depth 9|Set-Content $recordPath
$etl=Join-Path $out 'timeline.etl';$xml=Join-Path $out 'timeline.xml';$pnpLog=Join-Path $out 'pnp.jsonl'
$traceName='A1625-P0USB-S-'+[guid]::NewGuid().ToString('N');$traceStarted=$false;$child=$null
$oldPythonPath=$env:PYTHONPATH
function Stamp([string]$name){$record.timeline+=@([ordered]@{event=$name;utc=[DateTimeOffset]::UtcNow.ToString('o');tick=[Environment]::TickCount64})}
function Run-Reader([string]$mode,[string]$dir,[string]$armRecord){
    $args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$armScript,'-IdentityPath',$identityFull,'-OutputDirectory',$dir,'-Mode',$mode)
    if($armRecord){$args+=@('-ArmRecordPath',$armRecord)}
    $p=Start-Process $powershell -ArgumentList $args -PassThru -NoNewWindow
    if(-not $p.WaitForExit(10000)){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue;[void]$p.WaitForExit(5000);throw "$mode wrapper exceeded 10 seconds"}
    $code=$p.ExitCode;$p.Dispose();if($code -ne 0){throw "$mode wrapper failed: $code"}
}
try{
    & logman.exe start $traceName -p 'Microsoft-Windows-USB-UCX' 0xffffffffffffffff 0xff -o $etl -ets|Out-Null
    if($LASTEXITCODE -ne 0){throw "logman start failed: $LASTEXITCODE"};$traceStarted=$true;Stamp 'etw-started'
    $record.arm_attempts=1;Run-Reader 'Arm' (Join-Path $OutputDirectory 'arm') '';Stamp 'arm-confirmed'
    $armRecord=Join-Path $out 'arm/session.json';$arm=Get-Content $armRecord -Raw|ConvertFrom-Json
    if($arm.status -ne 'passed'){throw 'Arm record not passed'}
    if(([Environment]::TickCount64-$record.timeline[-1].tick) -gt 5000){throw 'COM start missed five-second post-arm bound'}
    $env:PYTHONPATH=$deps;$probeOut=Join-Path $out 'com-result';$child=Start-Process $python -ArgumentList @($probe,$identityFull,$probeOut) -PassThru -NoNewWindow
    $record.com_open_attempts=1;Stamp 'com-open-started'
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(60)
    do{
        $present=@(Get-PnpDevice -PresentOnly|Where-Object InstanceId -match '^USB\\VID_1209&PID_316D'|Select InstanceId,Status)
        ([ordered]@{utc=[DateTimeOffset]::UtcNow.ToString('o');devices=$present}|ConvertTo-Json -Compress -Depth 4)|Add-Content $pnpLog
        if($child -and -not $child.HasExited -and ([Environment]::TickCount64-$record.timeline[-1].tick) -ge 40000){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue;[void]$child.WaitForExit(5000);Stamp 'com-child-deadline'}
        Start-Sleep -Milliseconds 100
    }while([DateTimeOffset]::UtcNow -lt $deadline -and ([Environment]::TickCount64-$record.timeline[1].tick) -lt 50000)
    if($child -and -not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue;[void]$child.WaitForExit(5000)}
    Stamp 'report-started';$record.report_attempts=1
    Run-Reader 'Report' (Join-Path $OutputDirectory 'report') $armRecord;Stamp 'report-confirmed'
    $record.report=Get-Content (Join-Path $out 'report/session.json') -Raw|ConvertFrom-Json
    $record.status='passed'
}catch{$record.status='failed';$record.error=$_.Exception.Message}
finally{
    $env:PYTHONPATH=$oldPythonPath
    if($child){if(-not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue};$child.Dispose()}
    if($traceStarted){& logman.exe stop $traceName -ets|Out-Null}
    if(Test-Path $etl){& tracerpt.exe $etl -of XML -o $xml -y|Out-Null}
    $evidence=@($etl,$xml,$pnpLog,(Join-Path $out 'arm/session.json'),(Join-Path $out 'report/session.json'),(Join-Path $out 'com-result/result.json'))|Where-Object {Test-Path $_}
    $record.evidence_hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $evidence|Select Path,Hash)
    $record|ConvertTo-Json -Depth 9|Set-Content $recordPath
}
Write-Output "EP0 diagnostic trial : $($record.status)"
if($record.status -ne 'passed'){exit 1}
