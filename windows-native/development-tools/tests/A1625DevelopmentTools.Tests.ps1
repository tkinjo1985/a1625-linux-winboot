$modulePath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'development-tools\A1625DevelopmentTools.psm1'
Import-Module $modulePath -Force

Describe 'A1625 development-layer resolver' {
    It 'selects the minimal and development roots' {
        (@(Get-A1625DevelopmentProfile minimal) -contains 'git') | Should Be $true
        (@(Get-A1625DevelopmentProfile development) -contains 'build-base') | Should Be $true
        (@(Get-A1625DevelopmentProfile minimal) -contains 'build-base') | Should Be $false
    }
    It 'resolves direct and virtual APK dependencies once in dependency order' {
        $index = @(
            [pscustomobject]@{ Name='libx'; Version='1'; Depends=@(); Provides=@('so:libx.so.1=1') },
            [pscustomobject]@{ Name='git'; Version='1'; Depends=@('so:libx.so.1'); Provides=@() },
            [pscustomobject]@{ Name='ca'; Version='1'; Depends=@(); Provides=@() }
        )
        $resolved = @(Resolve-A1625AlpinePackages -Index $index -Roots @('git','ca'))
        $resolved.Name | Should Be @('libx','git','ca')
    }
    It 'uses the newest provider from the hash-pinned index' {
        $index = @(
            [pscustomobject]@{ Name='one'; Version='1'; Depends=@(); Provides=@('so:libx.so.1=1') },
            [pscustomobject]@{ Name='two'; Version='2'; Depends=@(); Provides=@('so:libx.so.1=2') },
            [pscustomobject]@{ Name='git'; Version='1'; Depends=@('so:libx.so.1'); Provides=@() }
        )
        @(Resolve-A1625AlpinePackages -Index $index -Roots @('git')).Name | Should Be @('two', 'git')
    }
}

Describe 'A1625 zram guardrail' {
    It 'pins A8-safe RAM-only zstd settings and refuses writeback' {
        $script = Get-A1625ZramScript
        $script | Should Match 'ZRAM_BYTES=\$\(\(768 \* 1024 \* 1024\)\)'
        $script | Should Match 'echo zstd'
        $script | Should Match 'ZRAM_PRIORITY=100'
        $script | Should Match 'backing_dev'
        $script | Should Not Match 'backing_dev\s*='
    }
}
