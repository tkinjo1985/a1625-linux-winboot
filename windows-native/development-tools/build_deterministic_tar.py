#!/usr/bin/env python3
"""Create a gzip tar with reproducible metadata for RAM package transport."""
import gzip
import json
import os
import posixpath
import sys
import tarfile

source, output = map(os.path.abspath, sys.argv[1:3])
with open(os.path.join(source, "manifest.json"), encoding="utf-8-sig") as f:
    manifest = json.load(f)
names = ["manifest.json", "a1625-zram-enable", "a1625-tool"] + [p["file"] for p in manifest["packages"]]
if len(names) != len(set(names)):
    raise ValueError("Duplicate package name")
expanded_bytes = 0
paths, links = set(), set()
for package in manifest["packages"]:
    with tarfile.open(os.path.join(source, package["file"]), "r:gz", ignore_zeros=True) as apk:
        for member in apk:
            name = member.name.removeprefix("./").rstrip("/")
            if not name or name.startswith("/") or ".." in name.split("/") or "\\" in name:
                raise ValueError(f"Unsafe APK path: {name}")
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise ValueError(f"Unsupported APK member: {name}")
            paths.add(name)
            if member.issym() or member.islnk():
                links.add(name)
                target = member.linkname
                resolved = posixpath.normpath(target.lstrip("/") if target.startswith("/") else posixpath.join(posixpath.dirname(name), target))
                if resolved.startswith("../") or resolved.split("/")[0] not in ("usr", "lib", "bin", "sbin", "etc"):
                    raise ValueError(f"Unsafe APK link: {name}")
            if member.isfile():
                expanded_bytes += member.size
for name in paths:
    parts = name.split("/")
    if any("/".join(parts[:i]) in links for i in range(1, len(parts))):
        raise ValueError(f"APK entry traverses a link: {name}")
with open(output, "wb") as raw:
    with gzip.GzipFile(filename="", fileobj=raw, mode="wb", mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode="w") as archive:
            for name in sorted(names):
                if os.path.basename(name) != name or name in (".", ".."):
                    raise ValueError("Unsafe package filename")
                path = os.path.join(source, name)
                if os.path.islink(path):
                    raise ValueError("Package input must be a regular file")
                info = archive.gettarinfo(path, arcname=name)
                info.mtime = 0
                info.mode = 0o644
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                with open(path, "rb") as item:
                    archive.addfile(info, item)
print(json.dumps({"expandedBytes": expanded_bytes, "archiveEntries": len(paths)}))
