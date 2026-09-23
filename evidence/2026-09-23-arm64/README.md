# Omarchy ARM64 validation — 2026-09-23

This directory contains unchanged selected artifacts from a native ROS 2 Lyrical build and runtime test in the Omarchy ARM64 Parallels VM. Read the [proof narrative](../../docs/proof.md) for commands, environment, and limitations.

- [`proof/report.json`](proof/report.json): both runtime directions passed, with five matching messages each.
- [`proof/cpp-to-python/`](proof/cpp-to-python/) and [`proof/python-to-cpp/`](proof/python-to-cpp/): actual talker/listener/observer logs, graph, and message intersections.
- [`final-build-summary.txt`](final-build-summary.txt) and [`build-service-status.txt`](build-service-status.txt): 225 packages completed and exit status 0.
- [`native-install-check.txt`](native-install-check.txt): imports, CLI checks, ARM64 executable, and system-SQLite evidence.
- [`check-built-install.sh`](check-built-install.sh): the historical VM-specific diagnostic that produced that output.
- [`executed-scripts.sha256`](executed-scripts.sha256): hashes captured from the executed scripts. The three installer/verifier basenames map to [`scripts/`](../../scripts/); the diagnostic basename maps to this directory.
- [`orocos-kdl-build.txt`](orocos-kdl-build.txt): local KDL/PyKDL revision and Python version.

Generic guest paths such as `/home/omarchy/ros2_lyrical` are retained as provenance. These files contain no VM credentials. Source/tool lockfiles are maintained in [`locks/`](../../locks/). This compact evidence does not include the large local build-history archive or complete system package inventory.
