"""The read-only inventory helper must create a new session output path."""
from pathlib import Path
import json
import os
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent
SCRIPT = HERE / 'Collect-TransportInventory.ps1'
source = SCRIPT.read_text()
assert source.index('New-Item -ItemType Directory') < source.index('Get-PnpDevice -PresentOnly')
assert 'Set-Content -LiteralPath $resolvedOutputPath' in source

powershell = Path(os.environ['SystemRoot']) / 'System32/WindowsPowerShell/v1.0/powershell.exe'
with tempfile.TemporaryDirectory() as directory:
    output = Path(directory) / 'new-session' / 'nested' / 'inventory.json'
    # The mock returns no devices. This exercises path creation and JSON
    # persistence without enumerating USB or opening a device.
    command = (
        'function Get-PnpDevice { param([switch]$PresentOnly) @() }; '
        f'& {str(SCRIPT)!r} -OutputPath {str(output)!r}'
    )
    result = subprocess.run(
        [str(powershell), '-NoProfile', '-NonInteractive',
         '-ExecutionPolicy', 'Bypass', '-Command', command],
        capture_output=True, text=True, check=True,
    )
    assert output.is_file()
    assert json.loads(output.read_text(encoding='utf-8-sig')) == []
    assert 'Saved 0 candidate(s). No port opened or packet sent.' in result.stdout

print('inventory helper creates nested output before mocked read-only enumeration')
