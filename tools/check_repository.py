#!/usr/bin/env python3
"""Check repository syntax and archived evidence integrity without running ROS.

This is a static artifact check, not a new native ROS build or runtime test.
It needs only Python's standard library and bash; it performs no network,
package installation, VM, or ROS actions.
"""
from __future__ import annotations

import argparse
import ast
import datetime as dt
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import unquote, urlsplit


EVIDENCE = Path("evidence/2026-09-23-arm64")
SHA1 = re.compile(r"[0-9a-f]{40}")
SHA256 = re.compile(r"[0-9a-f]{64}")
PAYLOAD = re.compile(r"Hello World: [0-9]+")


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def read_json(path: Path):
    return json.loads(path.read_text())


def python_blocks(shell: str) -> list[str]:
    return re.findall(r"^python\b[^\n]*<<'PY'\n(.*?)^PY$", shell, re.M | re.S)


def check_syntax(root: Path) -> str:
    files = sorted(path for directory in ("scripts", "tools", "evidence")
                   for path in (root / directory).rglob("*")
                   if path.suffix in {".py", ".sh"})
    require(files, "no scripts found")
    embedded_count = 0
    for path in files:
        source = path.read_text()
        label = str(path.relative_to(root))
        if path.suffix == ".py":
            compile(source, label, "exec")
        else:
            result = subprocess.run(["bash", "-n", str(path)], capture_output=True, text=True)
            require(result.returncode == 0, f"bash syntax failed: {label}\n{result.stderr}")
            for index, block in enumerate(python_blocks(source), 1):
                compile(block, f"{label}:Python-heredoc-{index}", "exec")
                embedded_count += 1
    return f"{len(files)} Python/Bash files and {embedded_count} embedded Python blocks"


def source_lock(path: Path) -> dict[str, str]:
    # Deliberately parse only the simple vcstool YAML structure used by this
    # checked-in lock, rejecting unknown syntax instead of guessing at YAML.
    repositories: dict[str, dict[str, str]] = {}
    current = None
    lines = path.read_text().splitlines()
    require(lines and lines[0] == "repositories:", "source lock has no repositories root")
    for number, line in enumerate(lines[1:], 2):
        if not line.strip():
            continue
        entry = re.fullmatch(r"  ([A-Za-z0-9_./-]+):", line)
        field = re.fullmatch(r"    (type|url|version): (\S+)", line)
        if entry:
            current = entry[1]
            require(current not in repositories, f"duplicate source lock entry: {current}")
            repositories[current] = {}
        elif field and current:
            require(field[1] not in repositories[current], f"duplicate lock field: {current}/{field[1]}")
            repositories[current][field[1]] = field[2]
        else:
            raise ValueError(f"unsupported source lock syntax at line {number}")
    for name, item in repositories.items():
        require(set(item) == {"type", "url", "version"}, f"incomplete source lock: {name}")
        require(item["type"] == "git" and item["url"].startswith("https://"),
                f"expected HTTPS Git source: {name}")
        require(bool(SHA1.fullmatch(item["version"])), f"source is not commit-pinned: {name}")
    return {name: item["version"] for name, item in repositories.items()}


def constraints(text: str) -> dict[str, str]:
    result = {}
    for line in text.splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)==([A-Za-z0-9_.+!-]+)", line.strip())
        require(match is not None, f"expected exact Python constraint, got {line!r}")
        name = re.sub(r"[-_.]+", "-", match[1]).lower()
        require(name not in result, f"duplicate Python constraint: {name}")
        result[name] = match[2]
    return result


def check_locks(root: Path) -> str:
    installer = (root / "scripts/install-ros2-lyrical.sh").read_text()
    assignments = [node for block in python_blocks(installer)
                   for node in ast.walk(ast.parse(block)) if isinstance(node, ast.Assign)
                   and any(isinstance(target, ast.Name) and target.id == "pinned_commits"
                           for target in node.targets)]
    require(len(assignments) == 1, "expected one embedded pinned_commits dictionary")
    node = assignments[0].value
    require(isinstance(node, ast.Dict), "pinned_commits must be a literal dictionary")
    keys = [ast.literal_eval(key) for key in node.keys]
    require(len(keys) == len(set(keys)), "duplicate embedded repository pin")
    embedded = ast.literal_eval(node)
    locked = source_lock(root / "locks/sources.lock.repos")
    require(len(locked) == 106, f"expected 106 source pins, found {len(locked)}")
    require(embedded == locked, "embedded source pins differ from locks/sources.lock.repos")
    blocks = re.findall(r"<<'PYTHON_TOOLS'\n(.*?)^PYTHON_TOOLS$", installer, re.M | re.S)
    require(len(blocks) == 1, "expected one embedded Python constraints block")
    tools = constraints((root / "locks/python-tools.lock.txt").read_text())
    require(len(tools) == 52, f"expected 52 Python constraints, found {len(tools)}")
    require(constraints(blocks[0]) == tools, "embedded Python constraints differ from lock file")
    return "106 source commits and 52 Python constraints agree with installer"


def check_executed_scripts(root: Path) -> str:
    expected = {
        "install-ros2-lyrical.sh": root / "scripts/install-ros2-lyrical.sh",
        "verify-ros2-lyrical.sh": root / "scripts/verify-ros2-lyrical.sh",
        "verify-ros2-lyrical.py": root / "scripts/verify-ros2-lyrical.py",
        "check-built-install.sh": root / EVIDENCE / "check-built-install.sh",
    }
    seen = set()
    for line in (root / EVIDENCE / "executed-scripts.sha256").read_text().splitlines():
        match = re.fullmatch(r"([0-9a-f]{64})  ([A-Za-z0-9_.-]+)", line)
        require(match is not None, "malformed executed-scripts.sha256 entry")
        digest, name = match.groups()
        require(name in expected and name not in seen, f"unexpected/duplicate executed script: {name}")
        require(hashlib.sha256(expected[name].read_bytes()).hexdigest() == digest,
                f"script bytes differ from the archived native run: {name}")
        seen.add(name)
    require(seen == set(expected), "executed script hashes are incomplete")
    native = (root / EVIDENCE / "native-install-check.txt").read_text()
    installer_digest = hashlib.sha256(expected["install-ros2-lyrical.sh"].read_bytes()).hexdigest()
    require(installer_digest + "  /home/omarchy/Projects/ros2-lyrical-installer/install-ros2-lyrical.sh" in native,
            "native install check does not record the current installer hash")
    return "all four executed script SHA-256 hashes match checked-in bytes"


def check_proof(root: Path) -> str:
    evidence = root / EVIDENCE
    proof = evidence / "proof"
    report = read_json(proof / "report.json")
    require(report["status"] == "PASS", "archived report did not pass")
    require(report["machine"] == "aarch64", "archived proof is not aarch64")
    require("ID=archarm" in report["os_release"], "archived proof is not Arch Linux ARM")
    environment = report["environment"]
    require(environment["ROS_DISTRO"] == "lyrical" and environment["ROS_VERSION"] == "2",
            "archived proof is not ROS 2 Lyrical")
    require(environment["RMW_IMPLEMENTATION"] == report["runtime_rmw"] == "rmw_fastrtps_cpp",
            "archived runtime did not use Fast DDS")
    require(environment["ROS_AUTOMATIC_DISCOVERY_RANGE"] == "LOCALHOST",
            "archived proof did not use local discovery")
    require(str(report["domain"]) == environment["ROS_DOMAIN_ID"], "ROS domain mismatch")
    require(report["minimum_matching_messages"] >= 5, "proof threshold is below five")
    require(dt.datetime.fromisoformat(report["started_utc"]) < dt.datetime.fromisoformat(report["completed_utc"]),
            "proof completion must follow its start")
    prefix = PurePosixPath(report["install_prefix"])
    require(prefix.is_absolute(), "install prefix must be absolute")
    required_packages = {"demo_nodes_cpp", "demo_nodes_py", "rclcpp", "rclpy", "rmw",
                         "ros_environment", "example_interfaces"}
    require(required_packages <= set(report["packages"]), "package provenance is incomplete")
    for name, package in report["packages"].items():
        require(PurePosixPath(package["prefix"]).is_relative_to(prefix), f"{name} is outside recorded install")
        require(package["version"] and SHA256.fullmatch(package["manifest_sha256"]),
                f"invalid package provenance: {name}")
    require(PurePosixPath(report["rclpy_module"]).is_relative_to(prefix), "rclpy is outside recorded install")

    directions = {"cpp-to-python": ("demo_nodes_cpp", "demo_nodes_py"),
                  "python-to-cpp": ("demo_nodes_py", "demo_nodes_cpp")}
    pairs = report["pairs"]
    require(len(pairs) == 2 and {pair["direction"] for pair in pairs} == set(directions),
            "expected exactly the two cross-language proof directions")
    counts = []
    for pair in pairs:
        label = pair["direction"]
        directory = proof / label
        require(pair["status"] == "PASS", f"{label}: archived pair did not pass")
        namespace = pair["namespace"]
        require(pair["topic"] == namespace + "/chatter" and pair["topic_type"] == "example_interfaces/msg/String",
                f"{label}: unexpected topic or type")
        publisher_package, listener_package = directions[label]
        expected_commands = [
            ["ros2", "run", package, executable, "--ros-args", "-r", "__node:=" + node,
             "-r", "__ns:=" + namespace]
            for package, executable, node in (
                (listener_package, "listener", "proof_listener"),
                (publisher_package, "talker", "proof_talker"))]
        require(pair["commands"] == expected_commands, f"{label}: not the upstream cross-language demo commands")
        talker = (directory / "talker.log").read_text()
        listener = (directory / "listener.log").read_text()
        observer_lines = (directory / "observer.log").read_text().splitlines()
        published = set(re.findall(r"Publishing: ['\"](Hello World: [0-9]+)['\"]", talker))
        heard = set(re.findall(r"I heard: \[(Hello World: [0-9]+)\]", listener))
        observed = {line for line in observer_lines if PAYLOAD.fullmatch(line)}
        intersection = published & heard & observed
        recorded = read_json(directory / "matching-messages.json")
        require(recorded == pair["matching_payloads"], f"{label}: matching messages disagree with report")
        require(len(recorded) == len(set(recorded)) >= 5, f"{label}: fewer than five distinct recorded payloads")
        require(set(recorded) <= intersection and len(intersection) >= report["minimum_matching_messages"],
                f"{label}: matching payloads are not present in all three real logs")
        require(pair["observer_received_count"] == len(observer_lines), f"{label}: observer count disagrees with log")
        graph = read_json(directory / "graph.json")
        require(graph == pair["graph"], f"{label}: graph file disagrees with report")
        endpoint = lambda name, ns: {"name": name, "namespace": ns, "type": pair["topic_type"]}
        require(endpoint("proof_talker", namespace) in graph["publishers"], f"{label}: publisher endpoint missing")
        require(endpoint("proof_listener", namespace) in graph["subscribers"], f"{label}: listener endpoint missing")
        observer_nodes = [node for node in graph["nodes"]
                          if node["name"].startswith("proof_observer_") and node["namespace"] == "/"]
        require(len(observer_nodes) == 1, f"{label}: independent observer node missing/ambiguous")
        require(endpoint(observer_nodes[0]["name"], "/") in graph["subscribers"], f"{label}: observer subscription missing")
        for node in ("proof_talker", "proof_listener"):
            require({"name": node, "namespace": namespace} in graph["nodes"], f"{label}: {node} graph node missing")
        counts.append(f"{label}: {len(intersection)} matching payloads")

    summary = (evidence / "final-build-summary.txt").read_text()
    require("Summary: 225 packages finished" in summary and "BUILD COMPLETE" in summary,
            "archived 225-package build completion missing")
    require("ExecMainStatus=0" in (evidence / "build-service-status.txt").read_text().splitlines(),
            "archived build service did not exit successfully")
    native = (evidence / "native-install-check.txt").read_text()
    for marker in ("ROS_NATIVE_INSTALL_CHECK_PASS", "FASTDDS_SYSTEM_SQLITE_CHECK_OK", "ARM aarch64",
                   "IMPORT_OK rclpy", "IMPORT_OK PyKDL", "ROS_CLI_HELP_OK"):
        require(marker in native, f"native install evidence missing {marker}")
    return "archived ARM64 Lyrical/Fast DDS PASS; " + "; ".join(counts)


def check_markdown_links(root: Path) -> str:
    checked = 0
    documents = sorted(path for path in root.rglob("*.md") if ".git" not in path.parts)
    for path in documents:
        text = re.sub(r"(?ms)^\s*(`{3,}|~{3,})[^\n]*\n.*?^\s*\1\s*$", "", path.read_text())
        # Inline links/images and reference definitions; external URLs and
        # heading-only anchors are not fetched or checked by this offline job.
        targets = re.findall(r"\[[^\]\n]*\]\(\s*(<[^>]+>|[^\s)]+)", text)
        targets += re.findall(r"(?m)^\s*\[[^\]\n]+\]:\s*(<[^>]+>|\S+)", text)
        for raw in targets:
            target = raw.strip("<>")
            url = urlsplit(target)
            if url.scheme or url.netloc or not url.path:
                continue
            destination = (path.parent / unquote(url.path)).resolve()
            label = f"{path.relative_to(root)}: {target}"
            require(destination.is_relative_to(root), f"Markdown file link escapes repository: {label}")
            require(destination.exists(), f"broken Markdown file link: {label}")
            checked += 1
    return f"{checked} relative file links in {len(documents)} Markdown documents"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1],
                        help="Repository to inspect (default: this script's repository)")
    root = parser.parse_args().root.resolve()
    print("Static repository validation; this does not build or run ROS.")
    failures = 0
    for check in (check_syntax, check_locks, check_executed_scripts, check_proof, check_markdown_links):
        try:
            print(f"PASS {check.__name__}: {check(root)}")
        except (ValueError, OSError, SyntaxError, KeyError, TypeError) as error:
            failures += 1
            print(f"FAIL {check.__name__}: {error}", file=sys.stderr)
    if failures:
        print(f"Repository validation failed ({failures} checks).", file=sys.stderr)
        return 1
    print("Repository artifact integrity checks passed. Native runtime evidence remains the archived run.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
