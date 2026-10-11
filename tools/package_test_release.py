#!/usr/bin/env python3
"""Check the compiled test APK and package source from its exact Git commit."""

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import zipfile


VERSION = "3.0.0"
VERSION_CODE = 30000
APPLICATION_ID = "cn.fafu.fafu_kebiao.v3test"
APP_LABEL = "FAFU v3 测试版"
SOURCE_ROOT = f"fafu_course_timetable-v{VERSION}"


def git(*args):
    return subprocess.check_output(["git", *args])


def manifest_attributes(apk):
    """Read literal attributes from Android's binary XML without SDK tooling."""
    with zipfile.ZipFile(apk) as archive:
        data = archive.read("AndroidManifest.xml")
    if len(data) < 8 or struct.unpack_from("<H", data)[0] != 3:
        raise ValueError("APK does not contain a compiled Android manifest")
    strings = []
    result = {}

    def u32(offset):
        return struct.unpack_from("<I", data, offset)[0]

    def length8(offset):
        value = data[offset]
        if value & 0x80:
            return ((value & 0x7f) << 8) | data[offset + 1], offset + 2
        return value, offset + 1

    def length16(offset):
        value = struct.unpack_from("<H", data, offset)[0]
        if value & 0x8000:
            return ((value & 0x7fff) << 16) | struct.unpack_from("<H", data, offset + 2)[0], offset + 4
        return value, offset + 2

    position = 8
    while position + 8 <= len(data):
        kind, header_size, size = struct.unpack_from("<HHI", data, position)
        if size < header_size or size < 8 or position + size > len(data):
            raise ValueError("Invalid Android manifest chunk")
        if kind == 1:
            count, flags, string_start = u32(position + 8), u32(position + 16), u32(position + 20)
            for index in range(count):
                start = position + string_start + u32(position + header_size + index * 4)
                if flags & 0x100:
                    _, start = length8(start)
                    length, start = length8(start)
                    strings.append(data[start:start + length].decode("utf-8"))
                else:
                    length, start = length16(start)
                    strings.append(data[start:start + length * 2].decode("utf-16le"))
        elif kind == 0x102:
            tag = strings[u32(position + 20)]
            attr_start, attr_size, attr_count = struct.unpack_from("<HHH", data, position + 24)
            if tag in {"manifest", "application"}:
                attributes = {}
                for index in range(attr_count):
                    offset = position + 16 + attr_start + index * attr_size
                    name, raw, value_type, value = u32(offset + 4), u32(offset + 8), data[offset + 15], u32(offset + 16)
                    attributes[strings[name]] = (
                        strings[raw] if raw != 0xffffffff else strings[value] if value_type == 3 else value
                    )
                result[tag] = attributes
        position += size
    return result


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_archive(destination, info):
    """Only committed files are included; tracked Base64 assets are decoded."""
    modes = git("ls-tree", "-r", "--full-tree", "-z", "HEAD").decode().split("\0")
    required = {
        "pubspec.yaml", "pubspec.lock", "lib/main.dart",
        "android/gradlew", "android/gradle/wrapper/gradle-wrapper.jar",
        "assets/icon/app_icon.png",
    }
    written = set()
    with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for entry in modes:
            if not entry:
                continue
            metadata, path = entry.split("\t", 1)
            mode, kind, blob = metadata.split()
            if kind != "blob":
                raise ValueError(f"Unsupported source entry: {path}")
            content = git("cat-file", "blob", blob)
            if path.endswith(".b64"):
                path = path[:-4]
                content = base64.b64decode(b"".join(content.split()), validate=True)
            if path in written or path.startswith("/") or ".." in Path(path).parts:
                raise ValueError(f"Invalid or duplicate source entry: {path}")
            written.add(path)
            item = zipfile.ZipInfo(f"{SOURCE_ROOT}/{path}")
            item.compress_type = zipfile.ZIP_DEFLATED
            permission = 0o755 if mode == "100755" or path == "android/gradlew" else 0o644
            item.external_attr = (0o100000 | permission) << 16
            archive.writestr(item, content)
        archive.writestr(
            f"{SOURCE_ROOT}/SOURCE_INFO.json",
            json.dumps(info, ensure_ascii=False, indent=2) + "\n",
        )
    missing = required - written
    if missing:
        raise ValueError(f"Source archive is incomplete: {sorted(missing)}")
    with zipfile.ZipFile(destination) as archive:
        if archive.testzip() is not None:
            raise ValueError("Source archive failed its integrity check")
        version_text = archive.read(f"{SOURCE_ROOT}/pubspec.yaml").decode()
        if not re.search(rf"(?m)^version:\s*{re.escape(VERSION)}\+{VERSION_CODE}\s*$", version_text):
            raise ValueError("Source version does not match APK")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    manifest = manifest_attributes(args.apk)
    expected = {"package": APPLICATION_ID, "versionName": VERSION, "versionCode": VERSION_CODE}
    for name, value in expected.items():
        if manifest.get("manifest", {}).get(name) != value:
            raise ValueError(f"APK {name} does not match the v3.0.0 test release")
    if manifest.get("application", {}).get("label") != APP_LABEL:
        raise ValueError("APK app label does not match the test release")
    if manifest.get("application", {}).get("debuggable", 0) != 0:
        raise ValueError("Expected a release-mode APK")

    commit = git("rev-parse", "HEAD").decode().strip()
    if os.environ.get("GITHUB_SHA", commit) != commit:
        raise ValueError("Build commit does not match the checked-out source")
    repo = os.environ.get("GITHUB_REPOSITORY", "awa11awa/fafu_course_timetable")
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    info = {
        "source_commit": commit,
        "version": VERSION,
        "version_code": VERSION_CODE,
        "application_id": APPLICATION_ID,
        "app_label": APP_LABEL,
        "build_mode": "release",
        "signing": "CI debug key; isolated test app",
        "flutter_version": "3.47.6",
        "workflow_run": f"https://github.com/{repo}/actions/runs/{run_id}" if run_id else None,
    }
    args.output.mkdir(parents=True, exist_ok=True)
    apk = args.output / f"FAFU-v{VERSION}-test.apk"
    source = args.output / f"fafu_course_timetable-v{VERSION}-source.zip"
    shutil.copyfile(args.apk, apk)
    source_archive(source, info)
    info["apk_sha256"] = sha256(apk)
    info["source_sha256"] = sha256(source)
    build_info = args.output / "BUILD_INFO.json"
    build_info.write_text(json.dumps(info, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    checksums = "".join(f"{sha256(path)}  {path.name}\n" for path in (apk, source, build_info))
    (args.output / "SHA256SUMS").write_text(checksums, encoding="utf-8")
    notes = Path("docs/releases/v3.0.0.md").read_text(encoding="utf-8")
    notes += f"\n构建提交：`{commit}`。\n"
    if info["workflow_run"]:
        notes += f"\n[自动测试与构建记录]({info['workflow_run']})\n"
    (args.output / "RELEASE_NOTES.md").write_text(notes, encoding="utf-8")
    print(json.dumps({"commit": commit, "version": VERSION, "package": APPLICATION_ID,
                      "apk_bytes": apk.stat().st_size, "source_bytes": source.stat().st_size}))


if __name__ == "__main__":
    main()
