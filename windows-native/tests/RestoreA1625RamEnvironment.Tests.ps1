$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$scriptPath = Join-Path $repoRoot 'windows-native\Restore-A1625RamEnvironment.ps1'

Describe 'Restore-A1625RamEnvironment safety preflight' {
    It 'parses as valid PowerShell' {
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
        $errors.Count | Should Be 0
    }

    It 'validates pinned artifacts without touching USB' {
        { & $scriptPath -ConfirmRamBoot -ValidateOnly } | Should Not Throw
    }

    It 'requires explicit RAM boot confirmation' {
        & pwsh.exe -NoProfile -File $scriptPath -ValidateOnly *> $null
        $LASTEXITCODE | Should Not Be 0
    }

    It 'contains exact A1625 identity gates and no persistent boot flag' {
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should Match 'CPID:7000'
        $source | Should Match 'BDID:34'
        $source | Should Match 'Resolve-ExpectedEcid'
        $source | Should Match 'device\.json'
        $source | Should Not Match '\[string\]\$ExpectedEcid\s*='
        $source | Should Match 'KernelPageSize:'
        $source | Should Match 'set -eu;'
        $source | Should Match 'FileShare\]::ReadWrite'
        $source | Should Not Match 'palera1n\s+-f'
    }

    It 'provides a parser-valid private device configuration helper' {
        $configScript = Join-Path $repoRoot 'windows-native\Set-A1625DeviceConfig.ps1'
        $tokens = $null
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($configScript, [ref]$tokens, [ref]$errors)
        $errors.Count | Should Be 0
        (Get-Content -LiteralPath $configScript -Raw) | Should Match 'expectedEcid'
    }

    It 'provides a strict PTY-backed interactive SSH wrapper' {
        $wrapper = Get-Content -LiteralPath (Join-Path $repoRoot 'windows-native\Enter-A1625Shell.ps1') -Raw
        $wrapper | Should Match "'-tt'"
        $wrapper | Should Match 'StrictHostKeyChecking=yes'
        $wrapper | Should Not Match 'StrictHostKeyChecking=no'
    }

    It 'integrates the PTY shell as an explicit post-restore option' {
        $source = Get-Content -LiteralPath $scriptPath -Raw
        $source | Should Match '\[switch\]\$EnterShell'
        $source | Should Match '& \$shellStarter -KnownHostsPath \$knownHosts'
        $source | Should Match 'Choose either -StartCodex or -EnterShell'
        $source | Should Match '\$codexStarter, \$shellStarter'
    }
}
