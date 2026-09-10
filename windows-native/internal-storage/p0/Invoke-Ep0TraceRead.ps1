param(
    [Parameter(Mandatory=$true)][string]$IdentityPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [ValidateSet('Arm','Report')][string]$Mode='Arm',
    [string]$ArmRecordPath
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputDirectory){throw 'Output directory already exists; no automatic repeat'}
$root=(Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$identityFull=(Resolve-Path -LiteralPath $IdentityPath).Path
$items=@((Get-Content -LiteralPath $identityFull -Raw | ConvertFrom-Json) | ForEach-Object {$_})
if($items.Count -ne 1){throw "Expected one identity candidate, found $($items.Count)"}
$identity=$items[0]
$devices=@(Get-PnpDevice -PresentOnly | Where-Object InstanceId -eq $identity.instance_id)
if($devices.Count -ne 1 -or $devices[0].Status -ne 'OK'){throw 'Current target identity is absent or not OK'}
$properties=@{}
Get-PnpDeviceProperty -InstanceId $devices[0].InstanceId | ForEach-Object {$properties[$_.KeyName]=$_.Data}
[string[]]$savedLocation=$identity.location
[string[]]$location=$properties['DEVPKEY_Device_LocationPaths']
if($identity.vid -ne 0x1209 -or $identity.pid -ne 0x316d -or
   $properties['DEVPKEY_Device_Service'] -ne 'usbser' -or
   $properties['DEVPKEY_Device_BusReportedDeviceDesc'] -notmatch '^m1n1 uartproxy ' -or
   $properties['DEVPKEY_Device_Parent'] -ne $identity.parent -or
   $savedLocation.Count -ne $location.Count -or
   @(Compare-Object $savedLocation $location -SyncWindow 0).Count -ne 0){throw 'Live EP0 trace identity/location gate failed'}
$physical=@($location | Where-Object {$_ -match '#USB\(([0-9]+)\)$'})
if($physical.Count -ne 1){throw 'Could not derive one physical hub connection port'}
$port=[int]([regex]::Match($physical[0],'#USB\(([0-9]+)\)$').Groups[1].Value)
$manifestPath=Join-Path $PSScriptRoot 'ep0-trace-reader-manifest.json'
$manifest=Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$source=(Resolve-Path -LiteralPath (Join-Path $root $manifest.source)).Path
$reader=(Resolve-Path -LiteralPath (Join-Path $root $manifest.executable)).Path
if((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $manifest.source_sha256 -or
   (Get-FileHash -Algorithm SHA256 -LiteralPath $reader).Hash -ne $manifest.executable_sha256){throw 'EP0 trace reader artifact gate failed'}
$outFull=[IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
if(-not $outFull.StartsWith($root+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Output directory must stay inside repository'}
New-Item -ItemType Directory -Path $outFull | Out-Null
$stdout=Join-Path $outFull 'stdout.txt';$stderr=Join-Path $outFull 'stderr.txt'
$record=[ordered]@{mode=$Mode;status='starting';attempts=0;
    com_opens=0;proxy_requests=0;ans_requests=0;nand_requests=0;
    identity=$identity;live_location=$location;hub_instance=$identity.parent;connection_port=$port;
    hashes=@(Get-FileHash -Algorithm SHA256 -LiteralPath $PSCommandPath,$manifestPath,$source,$reader,$identityFull | Select-Object Path,Hash)}
$recordPath=Join-Path $outFull 'session.json'
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
$process=$null
try{
    $record.attempts=1
    $process=Start-Process -FilePath $reader -ArgumentList @($identity.parent,[string]$port) -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if(-not $process.WaitForExit(5000)){
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        [void]$process.WaitForExit(5000)
        throw 'EP0 trace descriptor read exceeded 5-second deadline; no retry'
    }
    $record.exit_code=$process.ExitCode
    if($process.ExitCode -ne 0){throw "EP0 trace reader failed: $($process.ExitCode)"}
    $result=Get-Content -LiteralPath $stdout -Raw | ConvertFrom-Json
    if($result.format -ne 'P0E2' -or $result.boot_id -eq 0 -or $result.generation -ne 1 -or
       $result.trace -lt 0 -or $result.trace -gt 127){throw 'Malformed EP0 trace result'}
    if($Mode -eq 'Arm'){
        if(($result.flags -band 3) -ne 3 -or ($result.flags -band 4)){throw 'Diagnostic arm was not confirmed'}
    }else{
        if(-not $ArmRecordPath){throw 'Report mode requires ArmRecordPath'}
        $arm=Get-Content -LiteralPath (Resolve-Path -LiteralPath $ArmRecordPath) -Raw | ConvertFrom-Json
        if($arm.status -ne 'passed' -or $arm.mode -ne 'Arm' -or
           $result.boot_id -ne $arm.trace.boot_id -or $result.generation -ne $arm.trace.generation -or
           ($result.flags -band 4) -eq 0){throw 'Report is stale, mismatched, or not frozen'}
    }
    $record.trace=$result
    $record.status='passed'
}catch{$record.status='failed';$record.error=$_.Exception.Message}
finally{
    if($process){$process.Dispose()}
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $recordPath -Encoding utf8
}
Write-Output "EP0 trace read : $($record.status)"
if($record.status -ne 'passed'){exit 1}
