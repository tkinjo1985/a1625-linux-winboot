param(
    [Parameter(Mandatory=$true)][ValidateSet('Checkm8','Pongo','Payload')][string]$Stage,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
Set-Location $root
New-Item -ItemType Directory -Force $OutputDirectory | Out-Null
$cfg=Get-Content (Join-Path $env:LOCALAPPDATA 'AppleTvA1625/state/device.json') -Raw | ConvertFrom-Json
$pidText=if($Stage -eq 'Payload'){'4141'}else{'1227'}
$devices=@(Get-PnpDevice -PresentOnly | Where-Object InstanceId -match "^USB\\VID_05AC&PID_$pidText")
if($devices.Count -ne 1){throw 'Expected one target'}
$device=$devices[0];$id=$device.InstanceId
$service=(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_Service).Data
$expectedService=if($Stage -eq 'Pongo'){'WINUSB'}else{'libusbK'}
if($id -notmatch '(?i)CPID:7000(?:_|\b)' -or $id -notmatch '(?i)BDID:34(?:_|\b)' -or
   $id -notmatch "(?i)ECID:$([regex]::Escape($cfg.expectedEcid))(?:_|\b)" -or $device.Status -ne 'OK' -or
   $service -ne $expectedService) {throw "Identity/driver gate failed: expected $expectedService, got $service"}
if($Stage -eq 'Checkm8' -and $id -match 'YOLO:'){throw 'Expected clean DFU'}
if($Stage -eq 'Pongo' -and $id -notmatch 'YOLO:'){throw 'Expected YOLO DFU'}
[string[]]$location=(Get-PnpDeviceProperty -InstanceId $id -KeyName DEVPKEY_Device_LocationPaths).Data
$binding=Join-Path $OutputDirectory 'location.json'
if(Test-Path $binding){
    [string[]]$savedLocation=Get-Content $binding -Raw | ConvertFrom-Json
    if($savedLocation.Count -ne $location.Count -or @(Compare-Object $savedLocation $location -SyncWindow 0).Count -ne 0){throw 'USB location changed'}
}
else{$location | ConvertTo-Json | Set-Content $binding}
$openManifest=Get-Content artifacts/openra1n-win/build-manifest.json -Raw | ConvertFrom-Json
$exe=[string](Resolve-Path artifacts/openra1n-win/openra1n.exe)
$dll=[string](Resolve-Path artifacts/openra1n-win/libusb-1.0.dll)
if((Get-FileHash $exe).Hash -ne $openManifest.ExecutableSha256 -or (Get-FileHash $dll).Hash -ne $openManifest.LibusbSha256){throw 'Host hash mismatch'}
$arguments=@('--confirm-a1625','--expected-ecid',$cfg.expectedEcid)
$pattern='TRIGGER_HANDOFF|DFU_IDENTITY_REOPEN_LIMIT|Safety gate: refusing|Unrecognized DFU serial'
$files=@($PSCommandPath,'windows-native/Restore-A1625RamEnvironment.ps1',$exe,$dll)
if($Stage -eq 'Pongo'){$arguments=@('--upload-only')+$arguments;$pattern=$null}
if($Stage -eq 'Payload'){
    $manifestPath=Join-Path $PSScriptRoot 'build-manifest.json'
    $m=Get-Content $manifestPath -Raw | ConvertFrom-Json
    $payload=[string](Resolve-Path $m.m1n1_bin_path)
    $patchPath=Join-Path $PSScriptRoot 'm1n1-p0.patch'
    if((Get-FileHash $payload).Hash -ne $m.m1n1_bin_sha256 -or (Get-FileHash $patchPath).Hash -ne $m.patch_sha256 -or
       (git -C third_party/HoolockLinux-m1n1-p0 rev-parse HEAD) -ne $m.source_revision){throw 'P0 artifact gate failed'}
    $exe=[string](Resolve-Path windows-native/pongo-uploader/target/release/atv-pongo-uploader.exe)
    $arguments=@('upload',$payload,'--libusb',$dll,'--confirm-ram-boot');$pattern=$null
    $files+=@($exe,$manifestPath,$patchPath,$payload)
}
$recordPath=Join-Path $OutputDirectory "$Stage.json"
if(Test-Path $recordPath){throw 'Stage already recorded; no automatic repeat'}
$record=[ordered]@{stage=$Stage;status='starting';identity_verified=$true;service=$service;location=$location;hashes=@(Get-FileHash $files | Select-Object Path,Hash)}
$record | ConvertTo-Json -Depth 6 | Set-Content $recordPath
$ast=[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path windows-native/Restore-A1625RamEnvironment.ps1),[ref]$null,[ref]$null)
foreach($name in @('Get-LogDelta','Invoke-BoundedProcess')){
    $fn=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true) | Where-Object Name -eq $name
    Invoke-Expression ($fn.Extent.Text.Replace('Write-Host -NoNewline $delta; ',''))
}
$logRoot=Join-Path $env:LOCALAPPDATA 'AppleTvA1625/logs'
try{
    $r=Invoke-BoundedProcess -FilePath $exe -ArgumentList $arguments -TimeoutSeconds 120 -StopOnPattern $pattern
    $ok=switch($Stage){
        'Checkm8' {$r.Matched -and $r.Output -match 'Stage 0 succeeded' -and $r.Output -match 'TRIGGER_HANDOFF' -and $r.Output -notmatch 'Failed to read DFU USB serial string descriptor|check callback rejected it'}
        'Pongo' {$r.ExitCode -eq 0 -and $r.Output -match 'cpid=0x7000 yolo=yes' -and $r.Output -match 'Pongo upload finished'}
        'Payload' {$r.ExitCode -eq 0 -and $r.Output -match 'sent bootm to PongoOS'}
    }
    $record.status=if($ok){'passed'}else{'failed'}
    $record.stdout_log=$r.StdoutLog;$record.stderr_log=$r.StderrLog
}catch{$record.status='failed';$record.error=$_.Exception.Message}
finally{$record | ConvertTo-Json -Depth 6 | Set-Content $recordPath}
Write-Output "$Stage : $($record.status)"
if($record.status -ne 'passed'){exit 1}
