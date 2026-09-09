"""Check effective build configuration and symbols in an A1625 Wi-Fi ELF.

This is an offline build gate, not proof of boot, DMA or network operation.
Pass include/config/auto.conf captured from the build, not a requested fragment.
"""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path


REQUIRED_CONFIG = {
    'CONFIG_ARM64_4K_PAGES': 'y',
    'CONFIG_CFG80211': 'y',
    'CONFIG_BRCMFMAC': 'y',
    'CONFIG_BRCMFMAC_PCIE': 'y',
    'CONFIG_APPLE_DART': 'y',
    'CONFIG_PCI_MSI': 'y',
    'CONFIG_PCIE_APPLE_MSI_DOORBELL_ADDR': '0xbffff000',
    'CONFIG_USB_CONFIGFS_ACM': 'y',
    'CONFIG_USB_CONFIGFS_NCM': 'y',
}
REQUIRED_SYMBOLS = {'cfg80211_init', 'brcmf_pcie_probe', 'apple_dart_probe'}


def verify(vmlinux, config, nm):
    settings = dict(line.split('=', 1) for line in config.read_text().splitlines()
                    if line.startswith('CONFIG_') and '=' in line)
    failures = [f'{key}: expected {value}, found {settings.get(key, "unset")}'
                for key, value in REQUIRED_CONFIG.items()
                if settings.get(key) != value]
    for key in ('CONFIG_ARM64_16K_PAGES', 'CONFIG_ARM64_64K_PAGES'):
        if settings.get(key) == 'y':
            failures.append(f'{key} must be disabled')
    with vmlinux.open('rb') as source:
        header = source.read(20)
    if (len(header) != 20 or header[:6] != b'\x7fELF\x02\x01'
            or int.from_bytes(header[18:20], 'little') != 183):
        failures.append('Expected ELF64 little-endian AArch64 kernel')
    else:
        result = subprocess.run([str(nm), '--defined-only', '--format=posix',
                                 str(vmlinux)], check=True, capture_output=True,
                                text=True, timeout=120)
        symbols = {line.split()[0] for line in result.stdout.splitlines() if line.split()}
        failures.extend(f'Missing linked symbol: {symbol}'
                        for symbol in sorted(REQUIRED_SYMBOLS - symbols))
    if failures:
        raise ValueError('\n'.join(failures))
    with vmlinux.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    return {'build_gate': 'passed', 'vmlinux_sha256': digest,
            'effective_config_sha256': hashlib.sha256(config.read_bytes()).hexdigest(),
            'linked_symbols': sorted(REQUIRED_SYMBOLS),
            'scope': 'Configuration and linked symbols only; TCR machine-code review, '
                     'Image provenance, boot, DMA and Wi-Fi acceptance remain separate.'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--vmlinux', required=True, type=Path)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--nm', required=True, type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(verify(args.vmlinux, args.config, args.nm), indent=2))
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f'Wi-Fi kernel build gate failed:\n{error}\n')
