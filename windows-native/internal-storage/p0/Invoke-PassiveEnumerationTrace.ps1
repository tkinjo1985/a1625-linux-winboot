param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$ApprovedPayloadSha256,
    [ValidateRange(10,60)][int]$ObservationSeconds=35
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$session=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $session.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Output must stay inside repository'
}
if(-not(Test-Path -LiteralPath $session -PathType Container)){throw 'Boot session directory is missing'}
$checkm8=Join-Path $session 'Checkm8.json';$pongo=Join-Path $session 'Pongo.json';$payloadRecord=Join-Path $session 'Payload.json'
foreach($required in @($checkm8,$pongo)){
    if(-not(Test-Path -LiteralPath $required)){throw 'Checkm8 and Pongo records are required'}
    if((Get-Content -LiteralPath $required -Raw|ConvertFrom-Json).status -ne 'passed'){throw 'Prior boot stage did not pass'}
}
if(Test-Path -LiteralPath $payloadRecord){throw 'Payload stage already recorded; no automatic repeat'}

$manifestPath=Join-Path $PSScriptRoot 'build-manifest.json';$manifest=Get-Content -LiteralPath $manifestPath -Raw|ConvertFrom-Json
$patchPath=Join-Path $PSScriptRoot 'm1n1-p0.patch';$payload=(Resolve-Path -LiteralPath (Join-Path $root $manifest.m1n1_bin_path)).Path
if($ApprovedPayloadSha256 -notmatch '^[0-9A-Fa-f]{64}$' -or $ApprovedPayloadSha256 -ne $manifest.m1n1_bin_sha256){throw 'Approved payload hash mismatch'}
if((Get-FileHash -Algorithm SHA256 -LiteralPath $payload).Hash -ne $manifest.m1n1_bin_sha256 -or
   (Get-FileHash -Algorithm SHA256 -LiteralPath $patchPath).Hash -ne $manifest.patch_sha256){throw 'P0 artifact gate failed'}

$out=Join-Path $session 'passive-enumeration'
if(Test-Path -LiteralPath $out){throw 'Passive trace output exists; no automatic repeat'}
New-Item -ItemType Directory -Path $out|Out-Null
$bootScript=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'Invoke-UsbBootStage.ps1')).Path
$powershell=(Get-Process -Id $PID).Path;if(-not(Test-Path -LiteralPath $powershell)){throw 'Current PowerShell unavailable'}
$etl=Join-Path $out 'timeline.etl';$xml=Join-Path $out 'timeline.xml';$phasePath=Join-Path $out 'phases.jsonl';$recordPath=Join-Path $out 'session.json'
$trace='A1625-P0USB-ENUM-'+[guid]::NewGuid().ToString('N');$traceStarted=$false;$child=$null
$record=[ordered]@{mode='passive m1n1 enumeration trace';status='starting';observation_seconds=$ObservationSeconds;
 tool_descriptor_requests=0;index4_requests=0;com_opens=0;proxy_requests=0;nop_requests=0;ans_requests=0;nand_requests=0;
 approved_payload_sha256=$ApprovedPayloadSha256;hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath,$bootScript,$manifestPath,$patchPath,$payload|Select Path,Hash);timeline=@()}
$record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $recordPath
function Stamp([string]$name){
    $item=[ordered]@{event=$name;utc=[DateTimeOffset]::UtcNow.ToString('o');tick=[Environment]::TickCount64}
    $record.timeline+=@($item);$item|ConvertTo-Json -Compress|Add-Content -LiteralPath $phasePath
}
try{
    & logman.exe start $trace -p 'Microsoft-Windows-USB-UCX' 0xffffffffffffffff 0xff -o $etl -ets|Out-Null
    if($LASTEXITCODE){throw "logman start failed: $LASTEXITCODE"};$traceStarted=$true;Stamp 'etw-started-before-payload'
    $args=@('-NoProfile','-File',$bootScript,'-Stage','Payload','-OutputDirectory',$OutputDirectory,'-ApprovedPayloadSha256',$ApprovedPayloadSha256)
    $child=Start-Process $powershell -ArgumentList $args -PassThru -NoNewWindow;Stamp 'payload-stage-started'
    if(-not $child.WaitForExit(150000)){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue;[void]$child.WaitForExit(5000);throw 'Payload stage exceeded 150-second host deadline'}
    $record.payload_exit_code=$child.ExitCode;Stamp 'payload-stage-returned'
    if($child.ExitCode -ne 0){throw 'Payload stage failed; passive observation not extended'}
    Stamp 'passive-observation-started'
    $until=[DateTimeOffset]::UtcNow.AddSeconds($ObservationSeconds)
    while([DateTimeOffset]::UtcNow -lt $until){Start-Sleep -Milliseconds 250}
    Stamp 'passive-observation-complete';$record.status='passed'
}catch{$record.status='failed';$record.error=$_.Exception.Message}
finally{
    if($child){if(-not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue};$child.Dispose()}
    if($traceStarted){& logman.exe stop $trace -ets|Out-Null}
    if(Test-Path -LiteralPath $etl){& tracerpt.exe $etl -of XML -o $xml -y|Out-Null}
    $evidence=@($etl,$xml,$phasePath,$payloadRecord)|Where-Object{Test-Path -LiteralPath $_}
    $record.evidence_hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $evidence|Select Path,Hash)
    $record|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $recordPath
}
Write-Output "Passive enumeration trace : $($record.status)"
if($record.status -ne 'passed'){exit 1}
