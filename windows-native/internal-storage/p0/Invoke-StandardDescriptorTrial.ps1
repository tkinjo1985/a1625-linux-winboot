param(
    [Parameter(Mandatory=$true)][string]$IdentityPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [Parameter(Mandatory=$true)][string]$ApprovedPayloadSha256
)
$ErrorActionPreference='Stop'
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$out=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $out.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Output must stay inside repository'}
if(Test-Path $out){throw 'Output exists; no repeat'}
$manifestPath=Join-Path $PSScriptRoot 'build-manifest.json';$manifest=Get-Content $manifestPath -Raw|ConvertFrom-Json
if($ApprovedPayloadSha256 -ne $manifest.m1n1_bin_sha256){throw 'Approved payload hash mismatch'}
$identityFull=(Resolve-Path $IdentityPath).Path;$readerScript=(Resolve-Path (Join-Path $PSScriptRoot 'Invoke-Ep0TraceRead.ps1')).Path
$powershell=(Get-Process -Id $PID).Path;if(-not(Test-Path $powershell)){throw 'Current PowerShell unavailable'}
New-Item -ItemType Directory $out|Out-Null
$record=[ordered]@{mode='one product string control';status='starting';tool_descriptor_requests=0;com_opens=0;index4_requests=0;proxy_requests=0;nop_requests=0;ans_requests=0;nand_requests=0;
 approved_payload_sha256=$ApprovedPayloadSha256;passive_observation_seconds=35;hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath,$readerScript,$manifestPath,$identityFull|Select Path,Hash);timeline=@()}
$recordPath=Join-Path $out 'session.json';$record|ConvertTo-Json -Depth 9|Set-Content $recordPath
$etl=Join-Path $out 'timeline.etl';$xml=Join-Path $out 'timeline.xml';$trace='A1625-P0USB-STD-'+[guid]::NewGuid().ToString('N');$traceStarted=$false;$child=$null
function Stamp($name){$record.timeline+=@([ordered]@{event=$name;utc=[DateTimeOffset]::UtcNow.ToString('o');tick=[Environment]::TickCount64})}
try{
 & logman.exe start $trace -p 'Microsoft-Windows-USB-UCX' 0xffffffffffffffff 0xff -o $etl -ets|Out-Null;if($LASTEXITCODE){throw "logman start failed: $LASTEXITCODE"};$traceStarted=$true;Stamp 'etw-started'
 $readDir=Join-Path $OutputDirectory 'product';$args=@('-NoProfile','-File',$readerScript,'-IdentityPath',$identityFull,'-OutputDirectory',$readDir,'-Mode','Product')
 $child=Start-Process $powershell -ArgumentList $args -PassThru -NoNewWindow;$record.tool_descriptor_requests=1;Stamp 'product-reader-started'
 if(-not $child.WaitForExit(12000)){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue;[void]$child.WaitForExit(5000);throw 'Product wrapper did not terminate'}
 $record.reader_exit_code=$child.ExitCode;$readRecord=Join-Path $out 'product/session.json';if(Test-Path $readRecord){$record.read=Get-Content $readRecord -Raw|ConvertFrom-Json}
 if($record.reader_exit_code -eq 0){Stamp 'valid-product-returned';Start-Sleep -Seconds 2;$record.status='passed'}
 else{Stamp 'reader-failed-passive-window-started';$until=[DateTimeOffset]::UtcNow.AddSeconds(35);while([DateTimeOffset]::UtcNow -lt $until){Start-Sleep -Milliseconds 250};$record.status='failed'}
}catch{$record.status='failed';$record.error=$_.Exception.Message}
finally{
 if($child){if(-not $child.HasExited){Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue};$child.Dispose()}
 if($traceStarted){& logman.exe stop $trace -ets|Out-Null}
 if(Test-Path $etl){& tracerpt.exe $etl -of XML -o $xml -y|Out-Null}
 $evidence=@($etl,$xml,(Join-Path $out 'product/session.json'),(Join-Path $out 'product/phases.jsonl'),(Join-Path $out 'product/descriptor.raw'))|Where-Object{Test-Path $_}
 $record.evidence_hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $evidence|Select Path,Hash);$record|ConvertTo-Json -Depth 9|Set-Content $recordPath
}
Write-Output "Standard descriptor trial : $($record.status)";if($record.status -ne 'passed'){exit 1}
