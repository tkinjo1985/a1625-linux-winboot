param(
    [Parameter(Mandatory=$true)][string]$IdentityPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [int]$TimeoutSeconds = 15
)
$ErrorActionPreference = 'Stop'
if($TimeoutSeconds -lt 5 -or $TimeoutSeconds -gt 30){throw 'TimeoutSeconds must be 5..30'}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Output directory already exists; no automatic repeat'}

$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$identityFull=(Resolve-Path -LiteralPath $IdentityPath).Path
$items=@(Get-Content -LiteralPath $identityFull -Raw | ConvertFrom-Json)
if($items.Count -ne 1){throw "Expected one identity candidate, found $($items.Count)"}
$identity=$items[0]
$devices=@(Get-PnpDevice -PresentOnly | Where-Object InstanceId -eq $identity.instance_id)
if($devices.Count -ne 1 -or $devices[0].Status -ne 'OK'){throw 'Current target identity is absent or not OK'}
$service=(Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId -KeyName DEVPKEY_Device_Service).Data
[string[]]$location=(Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId -KeyName DEVPKEY_Device_LocationPaths).Data
[string[]]$savedLocation=$identity.location
if($identity.vid -ne 0x1209 -or $identity.pid -ne 0x316d -or $service -ne 'usbser' -or
   $identity.product -notmatch '^m1n1 uartproxy ' -or $savedLocation.Count -ne $location.Count -or
   @(Compare-Object $savedLocation $location -SyncWindow 0).Count -ne 0){throw 'Live COM identity gate failed'}

$python='C:\Users\tkinj\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
if(-not (Test-Path -LiteralPath $python)){throw 'Pinned Python executable missing'}
$probe=(Resolve-Path (Join-Path $PSScriptRoot 'trace_open.py')).Path
$deps=(Resolve-Path (Join-Path $root 'artifacts/ans-p0-python-deps')).Path
$outFull=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $outFull.StartsWith($root + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){
    throw 'Output directory must stay inside the repository'
}
New-Item -ItemType Directory -Path $outFull | Out-Null
$etl=Join-Path $outFull 'open.etl'
$xml=Join-Path $outFull 'open.xml'
$probeOut=Join-Path $outFull 'result'
$session='A1625-P0USB-' + [guid]::NewGuid().ToString('N')
$record=[ordered]@{mode='P0-USB traced COM open';status='starting';com_open_attempts=0;
    nop_requests=0;ans_requests=0;nand_read_requests=0;identity=$identity;
    hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath,$probe,$identityFull | Select-Object Path,Hash)}
$recordPath=Join-Path $outFull 'session.json'
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
$process=$null
$traceStarted=$false
try{
    & logman.exe start $session -p 'Microsoft-Windows-USB-UCX' 0xffffffffffffffff 0xff -o $etl -ets | Out-Null
    if($LASTEXITCODE -ne 0){throw "logman start failed: $LASTEXITCODE"}
    $traceStarted=$true
    $oldPythonPath=$env:PYTHONPATH
    $env:PYTHONPATH=$deps
    try{
        $process=Start-Process -FilePath $python -ArgumentList @($probe,$identityFull,$probeOut) -PassThru -NoNewWindow
    }finally{$env:PYTHONPATH=$oldPythonPath}
    $record.com_open_attempts=1
    if(-not $process.WaitForExit($TimeoutSeconds * 1000)){
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        [void]$process.WaitForExit(5000)
        $record.status='failed'
        $record.error="COM open exceeded $TimeoutSeconds-second deadline; exact child stopped; no retry"
    }else{
        $record.exit_code=$process.ExitCode
        $result=Get-Content -LiteralPath (Join-Path $probeOut 'result.json') -Raw | ConvertFrom-Json
        $record.com_configured=[bool]$result.com_configured
        $record.status=if($result.com_configured){'passed'}else{'failed'}
    }
}catch{
    $record.status='failed';$record.error=$_.Exception.Message
}finally{
    if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
    if($process){$process.Dispose()}
    if($traceStarted){& logman.exe stop $session -ets | Out-Null}
    if(Test-Path -LiteralPath $etl){& tracerpt.exe $etl -of XML -o $xml -y | Out-Null}
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
}
Write-Output "COM trace : $($record.status)"
if($record.status -ne 'passed'){exit 1}
