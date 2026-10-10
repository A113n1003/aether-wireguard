#!/usr/bin/env python3
"""将本机 Homebrew 工具冻结为可独立安装的 Tools 目录，不执行 VPN 操作。"""

import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import stat
import subprocess
import sys
import tempfile


CELLAR = Path("/opt/homebrew/Cellar")
TOOL_FORMULAS = {"bash": "bash", "wg": "wireguard-tools",
                 "wg-quick": "wireguard-tools", "wireguard-go": "wireguard-go"}
LIB_FORMULAS = {"readline", "ncurses", "gettext"}
SYSTEM_PREFIXES = ("/usr/lib/", "/System/Library/")
CLEAN_ENV = {"PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"}


def run(*arguments):
    result = subprocess.run(arguments, check=False, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            env=CLEAN_ENV)
    if result.returncode:
        raise RuntimeError(f"命令失败：{arguments[0]}：{result.stderr.strip()}")
    return result.stdout.strip()


def ensure_directory(path):
    """逐层拒绝符号链接，避免把构建结果写到重定向目录。"""
    current = Path(path.anchor)
    for part in path.parts[1:]:
        current /= part
        try:
            info = current.lstat()
        except FileNotFoundError:
            current.mkdir(mode=0o755)
            info = current.lstat()
        if not stat.S_ISDIR(info.st_mode):
            raise RuntimeError(f"输出路径必须为真实目录：{current}")


def source_file(path, formulas):
    resolved = Path(path).resolve(strict=True)
    try:
        relative = resolved.relative_to(CELLAR)
    except ValueError:
        raise RuntimeError(f"拒绝 Homebrew Cellar 之外的工具依赖：{path}")
    if len(relative.parts) < 3 or relative.parts[0] not in formulas:
        raise RuntimeError(f"拒绝未允许的工具依赖：{path}")
    if not stat.S_ISREG(resolved.lstat().st_mode):
        raise RuntimeError(f"工具源不是普通文件：{resolved}")
    return resolved


def copy_file(source, destination, executable=False):
    descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    try:
        before = os.fstat(descriptor)
        if not stat.S_ISREG(before.st_mode):
            raise RuntimeError(f"工具源不是普通文件：{source}")
        with os.fdopen(descriptor, "rb", closefd=False) as reader:
            with destination.open("xb") as writer:
                shutil.copyfileobj(reader, writer)
        after = os.fstat(descriptor)
        if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                after.st_size, after.st_mtime_ns, after.st_ctime_ns):
            raise RuntimeError(f"复制期间工具源发生变更：{source}")
        destination.chmod(0o755 if executable else 0o644)
    finally:
        os.close(descriptor)


def dependencies(path):
    lines = run("/usr/bin/otool", "-L", str(path)).splitlines()
    result = []
    for line in lines:
        if not line.startswith("\t"):
            continue
        match = re.fullmatch(r"\s+(.+) \(compatibility version [^)]+\)", line)
        if not match:
            raise RuntimeError(f"无法识别 Mach-O 依赖：{line}")
        result.append(match.group(1))
    return result


def replace_once(text, old, new):
    if text.count(old) != 1:
        raise RuntimeError("wg-quick 上游结构发生变化，停止打包以便复核")
    return text.replace(old, new, 1)


def freeze_wg_quick(path):
    text = path.read_text(encoding="utf-8")
    text = replace_once(
        text, 'export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${SELF%/*}:$PATH"',
        '# Aether: 使用随服务冻结的工具，禁止继承调用方 PATH。\n'
        'export PATH="${SELF%/*}:/usr/bin:/bin:/usr/sbin:/sbin"\n'
        'export WG_QUICK_USERSPACE_IMPLEMENTATION="${SELF%/*}/wireguard-go"\n'
        '[[ -x "${SELF%/*}/bash" && -x "${SELF%/*}/wg" && '
        '-x "$WG_QUICK_USERSPACE_IMPLEMENTATION" ]] || exit 1')
    text = replace_once(
        text, 'CONFIG_SEARCH_PATHS=( /etc/wireguard /usr/local/etc/wireguard '
        '/opt/homebrew/etc/wireguard )', 'CONFIG_SEARCH_PATHS=( )')
    text = replace_once(text, '\tCONFIG_FILE="$1"',
                        '\t[[ $1 == /* ]] || die "An absolute config path is required"\n'
                        '\tCONFIG_FILE="$1"')
    text = replace_once(
        text, '\t[[ $UID == 0 ]] || exec sudo -p "$PROGRAM must be run as root. '
        'Please enter the password for %u to continue: " -- "$BASH" -- "$SELF" "${ARGS[@]}"',
        '\t[[ $UID == 0 ]] || die "Run through the Aether privileged service"')
    path.write_text(text, encoding="utf-8")
    path.chmod(0o755)


def package(parent):
    if platform.system() != "Darwin":
        raise RuntimeError("工具冻结需要 macOS")
    parent = Path(os.path.abspath(parent))
    ensure_directory(parent)
    output = parent / "Tools"
    if output.exists() or output.is_symlink():
        raise RuntimeError(f"拒绝覆盖现有工具目录：{output}")
    stage = Path(tempfile.mkdtemp(prefix=".aether-tools-", dir=parent))
    try:
        stage.chmod(0o755)
        (stage / "bin").mkdir(mode=0o755)
        (stage / "lib").mkdir(mode=0o755)
        sources = {}
        library_names = {}
        pending = []
        for name, formula in TOOL_FORMULAS.items():
            source = source_file(f"/opt/homebrew/bin/{name}", {formula})
            target = stage / "bin" / name
            copy_file(source, target, executable=True)
            if name == "wg-quick":
                freeze_wg_quick(target)
            else:
                sources[source] = target
                pending.append(source)

        patches = {}
        while pending:
            source = pending.pop()
            target = sources[source]
            architecture = platform.machine()
            if architecture not in run("/usr/bin/lipo", "-archs", str(source)).split():
                raise RuntimeError(f"工具架构不匹配：{source}")
            for dependency in dependencies(source):
                if dependency.startswith(SYSTEM_PREFIXES):
                    # 前缀含分隔符；拒绝 ../ 绕过系统路径限制。
                    if os.path.normpath(dependency) != dependency:
                        raise RuntimeError(f"不安全的系统依赖路径：{dependency}")
                    continue
                if source in library_names.values() and Path(dependency).is_absolute():
                    if Path(dependency).resolve(strict=True) == source:
                        continue  # otool -L 也包含 dylib 自己的 LC_ID_DYLIB。
                if target.parent.name == "bin" and target.name != "bash":
                    raise RuntimeError(f"WireGuard 工具存在非系统依赖：{dependency}")
                library = source_file(dependency, LIB_FORMULAS)
                basename = library.name
                if basename in library_names and library_names[basename] != library:
                    raise RuntimeError(f"依赖文件同名冲突：{basename}")
                if basename not in library_names:
                    library_names[basename] = library
                    library_target = stage / "lib" / basename
                    copy_file(library, library_target)
                    sources[library] = library_target
                    pending.append(library)
                prefix = "@executable_path/../lib/" if target.parent.name == "bin" else "@loader_path/"
                patches.setdefault(target, []).extend(["-change", dependency, prefix + basename])

        for source, target in sources.items():
            arguments = patches.get(target, [])
            if target.parent.name == "lib":
                arguments += ["-id", "@loader_path/" + target.name]
            if arguments:
                run("/usr/bin/install_name_tool", *arguments, str(target))
            # 对原本仅引用系统库的工具也重新签名，形成一致的冻结快照。
            run("/usr/bin/codesign", "--force", "--sign", "-", str(target))
            run("/usr/bin/codesign", "--verify", "--strict", str(target))
            for dependency in dependencies(target):
                if dependency.startswith(SYSTEM_PREFIXES):
                    continue
                prefix = "@executable_path/../lib/" if target.parent.name == "bin" else "@loader_path/"
                if not dependency.startswith(prefix):
                    raise RuntimeError(f"冻结后仍有外部依赖：{dependency}")
                basename = dependency[len(prefix):]
                if "/" in basename or not (stage / "lib" / basename).is_file():
                    raise RuntimeError(f"冻结依赖缺失：{dependency}")

        bash = str(stage / "bin/bash")
        major = run(bash, "--noprofile", "--norc", "-c", 'printf "%s" "${BASH_VERSINFO[0]}"')
        if not major.isdigit() or int(major) < 4:
            raise RuntimeError("冻结 bash 必须为 4 或更新版本")
        run(bash, "--noprofile", "--norc", "-n", str(stage / "bin/wg-quick"))
        run(bash, "--noprofile", "--norc", str(stage / "bin/wg-quick"), "--help")
        run(str(stage / "bin/wg"), "--version")
        run(str(stage / "bin/wireguard-go"), "--version")
        files = {}
        for file in sorted(stage.rglob("*")):
            if file.is_symlink():
                raise RuntimeError(f"冻结目录含符号链接：{file}")
            if file.is_file():
                files[file.relative_to(stage).as_posix()] = hashlib.sha256(file.read_bytes()).hexdigest()
        manifest = {"schemaVersion": 1, "files": files}
        (stage / "tools-manifest.json").write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (stage / "tools-manifest.json").chmod(0o644)
        # 已存在的目录不覆盖；构建父目录必须属于可信的本机工作区。
        if output.exists() or output.is_symlink():
            raise RuntimeError(f"输出目录已被占用：{output}")
        stage.rename(output)
        print(f"已冻结 {len(files)} 个工具文件：{output}")
    finally:
        if stage.exists():
            shutil.rmtree(stage)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise RuntimeError("用法：package-helper-tools.py <输出父目录>")
        package(sys.argv[1])
    except (OSError, RuntimeError) as error:
        print(f"错误：{error}", file=sys.stderr)
        sys.exit(1)
