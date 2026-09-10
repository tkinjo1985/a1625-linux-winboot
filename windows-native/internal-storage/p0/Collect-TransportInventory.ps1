param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}
$records = @(Get-PnpDevice -PresentOnly | Where-Object InstanceId -match '^USB\\VID_1209&PID_316D' | ForEach-Object {
    $device = $_
    $properties = @{}
    Get-PnpDeviceProperty -InstanceId $device.InstanceId | ForEach-Object { $properties[$_.KeyName] = $_.Data }
    $interface = $null
    if ($device.InstanceId -match '&MI_([0-9A-F]{2})\\') { $interface = [Convert]::ToInt32($Matches[1],16) }
    $port = $null
    if ($device.FriendlyName -match '\((COM[0-9]+)\)') { $port = $Matches[1] }
    [ordered]@{
        port = $port; instance_id = $device.InstanceId; interface = $interface
        vid = 0x1209; pid = 0x316D; pnp_status = [string]$device.Status
        driver = $properties['DEVPKEY_Device_Service']
        driver_inf = $properties['DEVPKEY_Device_DriverInfPath']
        driver_version = $properties['DEVPKEY_Device_DriverVersion']
        location = $properties['DEVPKEY_Device_LocationPaths']
        parent = $properties['DEVPKEY_Device_Parent']
        product = $properties['DEVPKEY_Device_BusReportedDeviceDesc']
        serial = ($device.InstanceId -split '\\')[-1]
        hardware_ids = $properties['DEVPKEY_Device_HardwareIds']
        compatible_ids = $properties['DEVPKEY_Device_CompatibleIds']
        current_boot_verified = $false
    }
})
ConvertTo-Json -InputObject $records -Depth 6 | Set-Content -LiteralPath $resolvedOutputPath -Encoding utf8
# Keep individual serial/instance information in the artifact, out of public logs.
Write-Output "Saved $($records.Count) candidate(s). No port opened or packet sent."
