param([Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($OutputPath)
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$allowed = @('ans-baseline-kernel', 'ans-power-snapshot') | ForEach-Object {
    [IO.Path]::GetFullPath((Join-Path $repo "artifacts/$_")) + [IO.Path]::DirectorySeparatorChar
}
if (-not ($allowed | Where-Object { $target.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) })) {
    throw 'Host output is outside the isolated ANS build directories'
}
if ($target.EndsWith('.exe', [StringComparison]::OrdinalIgnoreCase)) { throw 'Expected extensionless output' }
$source = $target + '.exe'
if (-not [IO.File]::Exists($source)) { throw 'Compiled executable missing' }
# Use Windows filesystem APIs in one shell; no constructed cmd.exe commands.
if ([IO.File]::Exists($target)) { Remove-Item -LiteralPath $target -Force }
New-Item -ItemType HardLink -Path $target -Target $source | Out-Null
