Set-StrictMode -Version Latest

$script:AppleVendorId = '05AC'
$script:KnownProductIds = @{
    '12A7' = 'Apple USB service candidate (12A7)'
    '1227' = 'Apple DFU candidate (1227)'
    '4141' = 'PongoOS candidate (4141)'
}

function ConvertTo-AtvDeviceState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Device
    )

    process {
        $instanceId = [string]$Device.InstanceId
        $match = [regex]::Match($instanceId, 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})', 'IgnoreCase')
        if (-not $match.Success) {
            return
        }

        $vendorId = $match.Groups[1].Value.ToUpperInvariant()
        if ($vendorId -ne $script:AppleVendorId) {
            return
        }

        $productId = $match.Groups[2].Value.ToUpperInvariant()
        $mode = if ($script:KnownProductIds.ContainsKey($productId)) {
            $script:KnownProductIds[$productId]
        } else {
            'Other Apple USB device'
        }

        [pscustomobject]@{
            Status       = [string]$Device.Status
            FriendlyName = [string]$Device.FriendlyName
            VendorId     = $vendorId
            ProductId    = $productId
            Mode         = $mode
            InstanceId   = $instanceId
        }
    }
}

function Get-AtvUsbState {
    [CmdletBinding()]
    param()

    $devices = Get-PnpDevice -PresentOnly -ErrorAction Stop
    @($devices | ConvertTo-AtvDeviceState)
}

function Get-AtvUsbDetails {
    [CmdletBinding()]
    param()

    $states = @(Get-AtvUsbState)
    foreach ($state in $states) {
        # DFU serials contain square brackets (SRTG:[...]); -InstanceId treats
        # them as wildcard syntax. Select by exact string from present devices.
        $device = Get-PnpDevice -PresentOnly -ErrorAction Stop |
            Where-Object { $_.InstanceId -eq $state.InstanceId } |
            Select-Object -First 1
        if ($null -eq $device) {
            throw "Device disappeared during detail query: $($state.InstanceId)"
        }
        $properties = @($device | Get-PnpDeviceProperty -ErrorAction SilentlyContinue)

        $propertyMap = @{}
        foreach ($property in $properties) {
            $propertyMap[[string]$property.KeyName] = $property.Data
        }

        [pscustomobject]@{
            Status          = $state.Status
            Mode            = $state.Mode
            UsbId           = '{0}:{1}' -f $state.VendorId, $state.ProductId
            FriendlyName    = $state.FriendlyName
            DeviceDesc      = [string]$propertyMap['DEVPKEY_Device_DeviceDesc']
            BusDescription  = [string]$propertyMap['DEVPKEY_Device_BusReportedDeviceDesc']
            DriverService   = [string]$propertyMap['DEVPKEY_Device_Service']
            DriverVersion   = [string]$propertyMap['DEVPKEY_Device_DriverVersion']
            ProblemCode     = [string]$propertyMap['DEVPKEY_Device_ProblemCode']
            LocationPaths   = ($propertyMap['DEVPKEY_Device_LocationPaths'] -join ', ')
            ContainerId     = [string]$propertyMap['DEVPKEY_Device_ContainerId']
            Parent          = [string]$propertyMap['DEVPKEY_Device_Parent']
            IdentityEvidence = if (
                $state.ProductId -eq '12A7' -and
                [string]$propertyMap['DEVPKEY_Device_BusReportedDeviceDesc'] -eq 'AppleTV'
            ) {
                'AppleTV bus description + 05ac:12a7; record as owned-device baseline'
            } else {
                'VID/PID alone is not sufficient to identify the owned A1625'
            }
            InstanceId      = $state.InstanceId
        }
    }
}

function Save-AtvUsbBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $candidates = @(Get-AtvUsbDetails | Where-Object {
        $_.UsbId -eq '05AC:12A7' -and $_.BusDescription -eq 'AppleTV'
    })
    if ($candidates.Count -ne 1) {
        throw "Expected exactly one AppleTV 05ac:12a7 service device; found $($candidates.Count)."
    }

    $baseline = [ordered]@{
        RecordedAtUtc = [DateTimeOffset]::UtcNow.ToString('O')
        UserDeclaredModel = 'Apple TV HD A1625'
        UsbId = $candidates[0].UsbId
        BusDescription = $candidates[0].BusDescription
        InstanceId = $candidates[0].InstanceId
        ContainerId = $candidates[0].ContainerId
        LocationPaths = $candidates[0].LocationPaths
        Parent = $candidates[0].Parent
        DriverService = $candidates[0].DriverService
        DriverVersion = $candidates[0].DriverVersion
        Warning = 'DFU/Pongo re-enumeration must additionally be bound by CPID 0x7000 and ECID; VID/PID or location alone is insufficient.'
    }
    $baseline | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding utf8
    [pscustomobject]$baseline
}

function Get-AtvNativePreflight {
    [CmdletBinding()]
    param()

    $toolNames = @(
        'git', 'rustc', 'cargo', 'clang', 'cmake', 'ninja',
        'usbipd', 'irecovery', 'palera1n', 'dfu-util'
    )

    foreach ($name in $toolNames) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        [pscustomobject]@{
            Tool      = $name
            Available = $null -ne $command
            Path      = if ($null -ne $command) { [string]$command.Source } else { '' }
        }
    }
}

function Watch-AtvUsbState {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 30,

        [ValidateRange(100, 5000)]
        [int]$PollMilliseconds = 250
    )

    $deadline = [DateTimeOffset]::Now.AddSeconds($TimeoutSeconds)
    $previous = $null

    while ([DateTimeOffset]::Now -lt $deadline) {
        $states = @(Get-AtvUsbState)
        $signature = (($states | Sort-Object InstanceId | ForEach-Object {
            '{0}:{1}:{2}:{3}' -f $_.ProductId, $_.Status, $_.FriendlyName, $_.InstanceId
        }) -join '|')

        if ($signature -ne $previous) {
            if ($states.Count -eq 0) {
                [pscustomobject]@{
                    Timestamp = [DateTimeOffset]::Now
                    UsbId     = '-'
                    Status    = 'Not detected'
                    Mode      = 'No Apple USB device is currently present'
                }
            } else {
                foreach ($state in $states) {
                    [pscustomobject]@{
                        Timestamp = [DateTimeOffset]::Now
                        UsbId     = '{0}:{1}' -f $state.VendorId, $state.ProductId
                        Status    = $state.Status
                        Mode      = $state.Mode
                    }
                }
            }
            $previous = $signature
        }

        Start-Sleep -Milliseconds $PollMilliseconds
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-AtvDeviceState',
    'Get-AtvUsbState',
    'Get-AtvUsbDetails',
    'Get-AtvNativePreflight',
    'Save-AtvUsbBaseline',
    'Watch-AtvUsbState'
)
