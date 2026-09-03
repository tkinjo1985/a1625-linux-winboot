[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('diagnose', 'baseline', 'watch', 'help')]
    [string]$Command = 'diagnose',

    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 30,

    [string]$BaselinePath = (Join-Path $PSScriptRoot 'device-baseline.json')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'AtvNative.psm1') -Force

switch ($Command) {
    'diagnose' {
        Write-Output 'Apple TV USB devices'
        $details = @(Get-AtvUsbDetails)
        if ($details.Count -eq 0) {
            Write-Output 'No Apple USB device detected.'
        } else {
            $details | Format-List
        }

        Write-Output 'Native Windows preflight'
        Get-AtvNativePreflight | Format-Table -AutoSize

        Write-Output 'Safety boundary'
        Write-Output 'READ-ONLY: no driver changes, USB transfers, exploits, payload uploads, or storage writes are implemented.'
    }
    'baseline' {
        Write-Output 'Recording the uniquely detected AppleTV service-mode device (read-only USB query)...'
        Save-AtvUsbBaseline -Path $BaselinePath | Format-List
        Write-Output ("Baseline written to: {0}" -f (Resolve-Path -LiteralPath $BaselinePath).Path)
    }
    'watch' {
        Write-Output ("Watching Apple USB re-enumeration for {0} seconds (read-only)..." -f $TimeoutSeconds)
        Watch-AtvUsbState -TimeoutSeconds $TimeoutSeconds | Format-Table -AutoSize
    }
    'help' {
        Write-Output 'Usage: atv-native.ps1 diagnose'
        Write-Output '       atv-native.ps1 baseline [-BaselinePath .\device-baseline.json]'
        Write-Output '       atv-native.ps1 watch -TimeoutSeconds 30'
        Write-Output ''
        Write-Output 'This prototype is read-only and cannot run checkm8 or upload payloads.'
    }
}
