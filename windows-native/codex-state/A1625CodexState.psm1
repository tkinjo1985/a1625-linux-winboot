Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-A1625SshArguments {
    param(
        [Parameter(Mandatory)] [string]$SshKeyPath,
        [Parameter(Mandatory)] [string]$KnownHostsPath
    )

    foreach ($path in $SshKeyPath, $KnownHostsPath) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Required SSH file was not found: $path"
        }
    }
    @(
        '-T',
        '-i', [IO.Path]::GetFullPath($SshKeyPath),
        '-o', 'BatchMode=yes',
        '-o', 'ConnectTimeout=5',
        '-o', 'ServerAliveInterval=5',
        '-o', 'ServerAliveCountMax=3',
        '-o', 'StrictHostKeyChecking=yes',
        '-o', ('UserKnownHostsFile=' + [IO.Path]::GetFullPath($KnownHostsPath))
    )
}

function Invoke-A1625SshDownload {
    param(
        [Parameter(Mandatory)] [string[]]$SshArguments,
        [Parameter(Mandatory)] [string]$AppleTvAddress,
        [Parameter(Mandatory)] [string]$RemoteCommand,
        [ValidateRange(1, 600)] [int]$TimeoutSeconds = 180,
        [ValidateRange(1024, 268435456)] [long]$MaxBytes = 268435456
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command ssh.exe).Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $SshArguments) { [void]$startInfo.ArgumentList.Add($argument) }
    [void]$startInfo.ArgumentList.Add("root@$AppleTvAddress")
    [void]$startInfo.ArgumentList.Add($RemoteCommand)

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $output = [IO.MemoryStream]::new()
    try {
        if (-not $process.Start()) { throw 'Failed to start ssh.exe' }
        $copyTask = $process.StandardOutput.BaseStream.CopyToAsync($output)
        $errorTask = $process.StandardError.ReadToEndAsync()
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.WaitForExit(100)) {
            if ($output.Length -gt $MaxBytes -or $copyTask.IsFaulted -or [DateTime]::UtcNow -gt $deadline) {
                $process.Kill($true)
                [void]$process.WaitForExit(5000)
                throw 'SSH download exceeded its size/time limit or the output stream failed.'
            }
        }
        [void]$copyTask.GetAwaiter().GetResult()
        if ($output.Length -gt $MaxBytes) { throw 'SSH download exceeded its size limit.' }
        $stderr = $errorTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "SSH download failed with exit code $($process.ExitCode): $stderr"
        }
        $output.ToArray()
    }
    finally {
        $output.Dispose()
        $process.Dispose()
    }
}

function Invoke-A1625SshUpload {
    param(
        [Parameter(Mandatory)] [string[]]$SshArguments,
        [Parameter(Mandatory)] [string]$AppleTvAddress,
        [Parameter(Mandatory)] [string]$RemoteCommand,
        [Parameter(Mandatory)] [byte[]]$Payload,
        [ValidateRange(1, 600)] [int]$TimeoutSeconds = 180
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Command ssh.exe).Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $SshArguments) { [void]$startInfo.ArgumentList.Add($argument) }
    [void]$startInfo.ArgumentList.Add("root@$AppleTvAddress")
    [void]$startInfo.ArgumentList.Add($RemoteCommand)

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'Failed to start ssh.exe' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $writeTask = $process.StandardInput.BaseStream.WriteAsync($Payload, 0, $Payload.Length)
        if (-not $writeTask.Wait($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            [void]$process.WaitForExit(5000)
            throw 'SSH upload timed out while writing.'
        }
        [void]$writeTask.GetAwaiter().GetResult()
        $process.StandardInput.Close()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            [void]$process.WaitForExit(5000)
            throw 'SSH upload timed out waiting for the remote command.'
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "SSH upload failed with exit code $($process.ExitCode): $stderr"
        }
        $stdout.Trim()
    }
    finally {
        $process.Dispose()
    }
}

function Set-A1625StateDirectoryAcl {
    param([Parameter(Mandatory)] [string]$Path)

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    # Build only a DACL: copying an existing security descriptor can carry a
    # SACL and make repeat saves require the unrelated SeSecurityPrivilege.
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)
    $identities = @(
        [Security.Principal.WindowsIdentity]::GetCurrent().User,
        [Security.Principal.SecurityIdentifier]::new('S-1-5-18'),
        [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    )
    foreach ($identity in $identities) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $identity,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$acl.AddAccessRule($rule)
    }
    [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new([IO.Path]::GetFullPath($Path)), $acl)
}

function Write-A1625AtomicBytes {
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [byte[]]$Bytes
    )

    $nextPath = "$Path.next"
    $backupPath = "$Path.previous"
    $stream = [IO.FileStream]::new(
        $nextPath,
        [IO.FileMode]::Create,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None
    )
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
    if (Test-Path -LiteralPath $Path) {
        [IO.File]::Replace($nextPath, $Path, $backupPath, $true)
    }
    else {
        [IO.File]::Move($nextPath, $Path)
    }
}

function Get-A1625DpapiEntropy {
    [Text.Encoding]::UTF8.GetBytes('AppleTvA1625-CodexAuth-v1')
}

Export-ModuleMember -Function Get-A1625SshArguments, Invoke-A1625SshDownload,
    Invoke-A1625SshUpload, Set-A1625StateDirectoryAcl, Write-A1625AtomicBytes,
    Get-A1625DpapiEntropy
