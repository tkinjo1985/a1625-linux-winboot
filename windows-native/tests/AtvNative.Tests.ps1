Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path (Split-Path $PSScriptRoot -Parent) 'AtvNative.psm1'
Import-Module $modulePath -Force

$failures = [System.Collections.Generic.List[string]]::new()

function Assert-Equal {
    param(
        [Parameter(Mandatory)]$Expected,
        [Parameter(Mandatory)]$Actual,
        [Parameter(Mandatory)][string]$Name
    )

    if ($Expected -ne $Actual) {
        $failures.Add("$Name`: expected '$Expected', got '$Actual'")
    } else {
        Write-Output "PASS $Name"
    }
}

$normal = [pscustomobject]@{
    Status = 'OK'
    FriendlyName = 'Apple Mobile Device USB Device'
    InstanceId = 'USB\VID_05AC&PID_12A7\SERIAL'
} | ConvertTo-AtvDeviceState

$dfu = [pscustomobject]@{
    Status = 'OK'
    FriendlyName = 'Apple Mobile Device (DFU Mode)'
    InstanceId = 'USB\VID_05ac&PID_1227\DFU'
} | ConvertTo-AtvDeviceState

$pongo = [pscustomobject]@{
    Status = 'OK'
    FriendlyName = 'PongoOS USB Device'
    InstanceId = 'USB\VID_05AC&PID_4141\PONGO'
} | ConvertTo-AtvDeviceState

$nonApple = @([pscustomobject]@{
    Status = 'OK'
    FriendlyName = 'Other device'
    InstanceId = 'USB\VID_1234&PID_1227\OTHER'
} | ConvertTo-AtvDeviceState)

Assert-Equal 'Apple USB service candidate (12A7)' $normal.Mode 'normal mode candidate classification'
Assert-Equal '12A7' $normal.ProductId 'normal PID normalization'
Assert-Equal 'Apple DFU candidate (1227)' $dfu.Mode 'DFU candidate classification'
Assert-Equal 'PongoOS candidate (4141)' $pongo.Mode 'PongoOS candidate classification'
Assert-Equal 0 $nonApple.Count 'non-Apple filtering'

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ }
    exit 1
}

Write-Output 'All tests passed.'
