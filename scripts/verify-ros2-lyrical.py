#!/usr/bin/env python3
"""Run upstream ROS 2 demos; write auditable cross-language DDS evidence."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import platform
import random
import re
import shutil
import signal
import subprocess
import sys
import time
import uuid
import xml.etree.ElementTree as ET


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def file_hash(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def payloads(path):
    # Both official demo languages print this payload, with different quoting.
    return set(re.findall(r"Hello World: [0-9]+", path.read_text(errors="replace")))


def terminate_group(process):
    # ros2 run creates another process; signal the entire new process group.
    for sig, wait in ((signal.SIGINT, 3), (signal.SIGTERM, 2), (signal.SIGKILL, 1)):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            return
        try:
            process.wait(timeout=wait)
        except subprocess.TimeoutExpired:
            continue
        # The launcher may exit before its node. Continue if the group remains.
        try:
            os.killpg(process.pid, 0)
        except ProcessLookupError:
            return


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--install-prefix", type=Path, required=True,
                        help="Built workspace install/ directory; verifies package provenance")
    parser.add_argument("--output", type=Path, required=True,
                        help="New directory for this run; refuses to mix old evidence")
    parser.add_argument("--domain", type=int, default=random.SystemRandom().randint(20, 99))
    parser.add_argument("--messages", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=45.0, help="Seconds per direction")
    args = parser.parse_args()
    if not 0 <= args.domain <= 101 or args.messages < 2 or args.timeout <= 0:
        parser.error("domain must be 0..101, messages >=2, timeout >0")
    prefix = args.install_prefix.resolve(strict=True)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    report = {"status": "FAIL", "started_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "install_prefix": str(prefix), "python": sys.version,
              "python_executable": sys.executable, "platform": platform.platform(),
              "machine": platform.machine(), "domain": args.domain,
              "minimum_matching_messages": args.messages, "pairs": []}
    observer = None
    initialized = False
    children = []
    handles = []
    try:
        if os.environ.get("ROS_DISTRO") != "lyrical":
            raise RuntimeError(f"Expected ROS_DISTRO=lyrical, got {os.environ.get('ROS_DISTRO')!r}; source the Lyrical install first")
        if not shutil.which("ros2"):
            raise RuntimeError("ros2 is not on PATH; source the built install first")
        os.environ.update(ROS_DOMAIN_ID=str(args.domain),
                          ROS_AUTOMATIC_DISCOVERY_RANGE="LOCALHOST",
                          RCUTILS_COLORIZED_OUTPUT="0", RCUTILS_LOGGING_BUFFERED_STREAM="0",
                          PYTHONUNBUFFERED="1", ROS_LOG_DIR=str(output / "ros-logs"))
        os.environ.pop("ROS_STATIC_PEERS", None)
        # ROS_LOCALHOST_ONLY is superseded by AUTOMATIC_DISCOVERY_RANGE.
        os.environ.pop("ROS_LOCALHOST_ONLY", None)
        import rclpy
        from rclpy.utilities import get_rmw_implementation_identifier
        from ament_index_python.packages import get_package_prefix
        from example_interfaces.msg import String
        report["environment"] = {name: os.environ.get(name) for name in (
            "ROS_DISTRO", "ROS_VERSION", "ROS_DOMAIN_ID", "ROS_AUTOMATIC_DISCOVERY_RANGE",
            "RMW_IMPLEMENTATION", "AMENT_PREFIX_PATH", "COLCON_PREFIX_PATH")}
        report["os_release"] = Path("/etc/os-release").read_text()
        report["packages"] = {}
        for package in ("demo_nodes_cpp", "demo_nodes_py", "rclcpp", "rclpy", "rmw", "ros_environment", "example_interfaces"):
            package_prefix = Path(get_package_prefix(package)).resolve()
            if not package_prefix.is_relative_to(prefix):
                raise RuntimeError(f"{package} resolved outside requested source install: {package_prefix}")
            manifest = package_prefix / "share" / package / "package.xml"
            root = ET.parse(manifest).getroot()
            report["packages"][package] = {
                "version": root.findtext("version"), "prefix": str(package_prefix),
                "manifest_sha256": file_hash(manifest)}
        report["runtime_rmw"] = get_rmw_implementation_identifier()
        if report["runtime_rmw"] != "rmw_fastrtps_cpp":
            raise RuntimeError(f"Expected rmw_fastrtps_cpp, got {report['runtime_rmw']!r}")
        report["rclpy_module"] = str(Path(rclpy.__file__).resolve())
        token = uuid.uuid4().hex[:12]
        rclpy.init(args=[])
        initialized = True
        observer = rclpy.create_node("proof_observer_" + token)
        for label, publisher_package, listener_package in (
            ("cpp-to-python", "demo_nodes_cpp", "demo_nodes_py"),
            ("python-to-cpp", "demo_nodes_py", "demo_nodes_cpp"),
        ):
            pair_output = output / label
            pair_output.mkdir()
            namespace = "/lyrical_proof_" + token + "/" + label.replace("-", "_")
            topic = namespace + "/chatter"
            observed = []
            observer_log = (pair_output / "observer.log").open("w", buffering=1)
            handles.append(observer_log)

            def record(message):
                observed.append(message.data)
                observer_log.write(message.data + "\n")

            subscription = observer.create_subscription(String, topic, record, 10)
            pair = {"direction": label, "topic": topic, "topic_type": "example_interfaces/msg/String",
                    "namespace": namespace, "commands": [], "status": "FAIL"}
            report["pairs"].append(pair)
            pair_children = []
            try:
                # Start the subscriber first; do not depend on receiving message zero.
                for package, executable, node_name, log_name in (
                    (listener_package, "listener", "proof_listener", "listener.log"),
                    (publisher_package, "talker", "proof_talker", "talker.log"),
                ):
                    command = ["ros2", "run", package, executable, "--ros-args", "-r",
                               "__node:=" + node_name, "-r", "__ns:=" + namespace]
                    pair["commands"].append(command)
                    handle = (pair_output / log_name).open("w", buffering=1)
                    handles.append(handle)
                    process = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT,
                                               start_new_session=True)
                    children.append(process)
                    pair_children.append(process)
                deadline = time.monotonic() + args.timeout
                matched = []
                graph = {}
                while time.monotonic() < deadline:
                    rclpy.spin_once(observer, timeout_sec=0.2)
                    for process in pair_children:
                        if process.poll() is not None:
                            raise RuntimeError(f"{label}: upstream demo exited early with status {process.returncode}")
                    publisher_info = observer.get_publishers_info_by_topic(topic)
                    subscriber_info = observer.get_subscriptions_info_by_topic(topic)
                    graph = {
                        "nodes": sorted([{"name": name, "namespace": ns} for name, ns in
                                         observer.get_node_names_and_namespaces()], key=lambda x: (x["namespace"], x["name"])),
                        "publishers": [{"name": x.node_name, "namespace": x.node_namespace,
                                        "type": x.topic_type} for x in publisher_info],
                        "subscribers": [{"name": x.node_name, "namespace": x.node_namespace,
                                         "type": x.topic_type} for x in subscriber_info],
                    }
                    matched = sorted(payloads(pair_output / "talker.log") &
                                     payloads(pair_output / "listener.log") & set(observed),
                                     key=lambda x: int(x.rsplit(" ", 1)[1]))
                    publisher_seen = any(x.node_name == "proof_talker" and x.node_namespace == namespace for x in publisher_info)
                    listener_seen = any(x.node_name == "proof_listener" and x.node_namespace == namespace for x in subscriber_info)
                    if len(matched) >= args.messages and publisher_seen and listener_seen:
                        break
                pair["matching_payloads"] = matched
                pair["observer_received_count"] = len(observed)
                pair["graph"] = graph
                write_json(pair_output / "graph.json", graph)
                write_json(pair_output / "matching-messages.json", matched)
                if len(matched) < args.messages:
                    raise RuntimeError(f"{label}: only {len(matched)} messages matched all three logs within {args.timeout:g}s")
                if not (publisher_seen and listener_seen):
                    raise RuntimeError(f"{label}: required upstream endpoints absent from ROS graph")
                pair["status"] = "PASS"
                print(f"PASS {label}: {len(matched)} identical published/listened/observed payloads", flush=True)
                for payload in matched:
                    print("  " + payload, flush=True)
            finally:
                for process in reversed(pair_children):
                    terminate_group(process)
                    children.remove(process)
                observer.destroy_subscription(subscription)
                observer_log.close()
        report["status"] = "PASS"
    except BaseException as error:
        report["error"] = f"{type(error).__name__}: {error}"
        print(report["error"], file=sys.stderr, flush=True)
    finally:
        for process in reversed(children):
            terminate_group(process)
        if observer is not None:
            observer.destroy_node()
        if initialized:
            rclpy.try_shutdown()
        for handle in handles:
            if not handle.closed:
                handle.close()
        report["completed_utc"] = dt.datetime.now(dt.timezone.utc).isoformat()
        write_json(output / "report.json", report)
        print(f"{report['status']}: evidence at {output}", flush=True)
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    def interrupt(signum, frame):
        raise KeyboardInterrupt(f"signal {signum}")
    signal.signal(signal.SIGTERM, interrupt)
    raise SystemExit(main())
