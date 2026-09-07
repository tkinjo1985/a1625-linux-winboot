#Requires -Version 7.0
[CmdletBinding()] param([string]$StateDirectory=(Join-Path $env:LOCALAPPDATA 'AppleTvA1625\ram-state'),[Parameter(Mandatory)][string]$PayloadPath,[Parameter(Mandatory)][string]$RuntimePath)
Set-StrictMode -Version Latest; $ErrorActionPreference='Stop'; Import-Module (Join-Path $PSScriptRoot 'A1625RamState.psm1') -Force
Test-A1625RamStateSnapshot -StateDirectory $StateDirectory -PayloadPath $PayloadPath -RuntimePath $RuntimePath
