# Native ROS 2 Lyrical validation

**PASS — September 23, 2026.** ROS 2 Lyrical `ros_base`, its CLI, and the upstream C++/Python demos were built and run natively in an Omarchy ARM64 Parallels VM. The final colcon invocation completed **225 packages** and the installer exited with status **0**.

## Runtime results

| Test | Result | Payloads matched in publisher, listener, and independent observer |
| --- | --- | --- |
| C++ talker → Python listener | PASS | `Hello World: 1` through `Hello World: 5` |
| Python talker → C++ listener | PASS | `Hello World: 0` through `Hello World: 4` |

The test ran from **17:59:03 to 17:59:15 UTC**. The [raw report](../evidence/2026-09-23-arm64/proof/report.json) records exact commands, package versions and prefixes, graph endpoints, matching payloads, and timestamps. It verifies `ROS_DISTRO=lyrical`, ARM64 runtime provenance, and `rmw_fastrtps_cpp`. The verifier checks both language directions against a third subscriber using unique namespaces and localhost discovery. Domain 59 was randomly selected for this run.

Actual first C++ → Python messages:

```text
[INFO] [1790186345.080674300] [lyrical_proof_336d77a2996e.cpp_to_python.proof_talker]: Publishing: 'Hello World: 1'
[INFO] [1790186345.103950737] [lyrical_proof_336d77a2996e.cpp_to_python.proof_listener]: I heard: [Hello World: 1]
```

Actual first Python → C++ messages:

```text
[INFO] [1790186350.850942135] [lyrical_proof_336d77a2996e.python_to_cpp.proof_talker]: Publishing: "Hello World: 0"
[INFO] [1790186350.851798725] [lyrical_proof_336d77a2996e.python_to_cpp.proof_listener]: I heard: [Hello World: 0]
```

| Direction | Publisher | Listener | Independent observer | Graph |
| --- | --- | --- | --- | --- |
| C++ → Python | [log](../evidence/2026-09-23-arm64/proof/cpp-to-python/talker.log) | [log](../evidence/2026-09-23-arm64/proof/cpp-to-python/listener.log) | [log](../evidence/2026-09-23-arm64/proof/cpp-to-python/observer.log) | [JSON](../evidence/2026-09-23-arm64/proof/cpp-to-python/graph.json) |
| Python → C++ | [log](../evidence/2026-09-23-arm64/proof/python-to-cpp/talker.log) | [log](../evidence/2026-09-23-arm64/proof/python-to-cpp/listener.log) | [log](../evidence/2026-09-23-arm64/proof/python-to-cpp/observer.log) | [JSON](../evidence/2026-09-23-arm64/proof/python-to-cpp/graph.json) |

Each direction used `example_interfaces/msg/String`. The verifier stopped the demo processes after gathering evidence; interrupt messages at the ends of the logs are expected cleanup.

## Build environment

| Item | Observed value |
| --- | --- |
| Guest | Omarchy `4.0.0.alpha`, Arch Linux ARM |
| CPU / memory | 4 virtual CPUs / 8 GiB RAM |
| Build concurrency | 2 compiler jobs, sequential package executor |
| Running kernel | `7.2.2-2-aarch64-ARCH` |
| Toolchain | GCC 16.1.1, CMake 4.4.3, Python 3.14.7 |
| Demo package versions | `demo_nodes_cpp` and `demo_nodes_py` 0.37.9 |
| Client libraries | `rclcpp` 32.0.3, `rclpy` 10.0.11 |
| Source selection | 106 ROS repositories, pinned to exact commits |
| KDL / PyKDL | 1.5.4, commit `84b086838dea2b1132064517a61017d30945f1d3` |

The [build summary](../evidence/2026-09-23-arm64/final-build-summary.txt) and [service status](../evidence/2026-09-23-arm64/build-service-status.txt) establish final completion. The reported **3 min 15 sec** is the final resumed colcon invocation, not the initial build duration. Seventeen packages emitted nonfatal CMake warnings; no packages failed in the final invocation.

The [native installation check](../evidence/2026-09-23-arm64/native-install-check.txt) passed Python imports for `rclpy`, `launch`, `launch_ros`, `rosbag2_py`, `tf2_ros`, `PyKDL`, and `osrf_pycommon`; a PyKDL vector calculation; and ROS/launch/bag CLI help commands. It identifies the C++ talker as an ARM64 ELF executable and confirms Fast DDS links system SQLite with persistence enabled.

The [executed-script hashes](../evidence/2026-09-23-arm64/executed-scripts.sha256) match the installer and verifier in `scripts/`. The fourth hash identifies the archived [native-check helper](../evidence/2026-09-23-arm64/check-built-install.sh). That helper contains paths specific to the measured VM and is retained as historical evidence; use the portable runtime verifier for a new installation.

## Reproduce

After installing, run from this repository root:

```bash
bash scripts/verify-ros2-lyrical.sh ~/ros2_lyrical/install ~/new-lyrical-proof
```

The output directory must not exist. See [installation instructions](installation.md) for building and running the demos manually.

## Limits of this result

The build was developed and resumed on one existing ARM64 Omarchy VM. The final script was not rerun on a second pristine OS image. x86_64 execution and a post-upgrade guest reboot were not tested. The system package set remains rolling even though ROS source and Python tool versions are pinned.

This validates ROS Base and cross-language DDS communication. It does not validate RViz, Gazebo, every ROS API, physical robot drivers, real-time behavior, or DDS persistence semantics. Package unit tests and LTTng tracing were disabled. Fast DDS persistence was confirmed enabled and linked to system SQLite, but persistence behavior was not exercised.

The public repository contains compact, unchanged raw runtime evidence and selected build receipts. Large build archives, the full system package inventory, VM files, and local access notes are not included. GitHub Actions checks the integrity of this evidence; it does not rerun the native VM build.
