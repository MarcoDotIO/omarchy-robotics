# Omarchy Robotics

[![Repository checks](https://github.com/MarcoDotIO/omarchy-robotics/actions/workflows/repository-checks.yml/badge.svg)](https://github.com/MarcoDotIO/omarchy-robotics/actions/workflows/repository-checks.yml)

Build **ROS 2 Lyrical ROS Base** natively on Omarchy and Arch Linux. This repository provides a resumable source installer, pinned ROS and Python tooling versions, and a verifier that runs the upstream C++ and Python talker/listener demos.

## Verified on Omarchy ARM64

On September 23, 2026, the installer completed **225 packages** in an Omarchy ARM64 Parallels VM. Both communication tests passed with five matching messages, independently observed by a third ROS node:

| Test | Result |
| --- | --- |
| C++ talker → Python listener | PASS |
| Python talker → C++ listener | PASS |

Read the [execution proof](docs/proof.md) and [raw report](evidence/2026-09-23-arm64/proof/report.json). The checked-in installer and verifier match the scripts used for that run. The CI badge covers repository integrity and syntax; it does not represent a fresh ROS build.

## Install

Run **inside Omarchy**, as your normal user, in a fresh Bash shell:

```bash
git clone https://github.com/MarcoDotIO/omarchy-robotics.git
cd omarchy-robotics
bash scripts/install-ros2-lyrical.sh --jobs 2
```

The installer performs a full `pacman -Syu` using sudo, installs dependencies, and compiles into `~/ros2_lyrical`. It leaves shell startup files unchanged. Allow at least **12 GiB of free disk space**; the validated VM had **8 GiB RAM** and used **two compiler jobs**.

See [installation options, dependencies, and compatibility notes](docs/installation.md). Rerun the same command to resume a failed build.

## Run the demos

In one terminal:

```bash
source ~/ros2_lyrical/env.bash
ros2 run demo_nodes_cpp talker
```

In another:

```bash
source ~/ros2_lyrical/env.bash
ros2 run demo_nodes_py listener
```

Press Ctrl+C to stop. To run both cross-language directions and save independently checked evidence:

```bash
bash scripts/verify-ros2-lyrical.sh ~/ros2_lyrical/install ~/lyrical-proof
```

Use a new output directory for each run.

## Scope

| Component / platform | Status |
| --- | --- |
| ROS Base, ROS CLI, C++ and Python demos | Built and exercised on ARM64 |
| Middleware | Fast DDS (`rmw_fastrtps_cpp`) |
| Omarchy ARM64 / Arch Linux ARM | Tested in one existing Parallels VM |
| x86_64 Omarchy / Arch | Accepted by the installer; execution not yet tested |
| RViz, Gazebo, full ROS desktop | Outside this installer |
| Physical robots and drivers | Not tested |

Arch is outside the [official Lyrical platform list](https://github.com/ros2/ros2_documentation/blob/rolling/source/Get-Started/Releases/lyrical/supported-platforms.rst). This is a community source-build integration. ROS source revisions and Python tools are pinned; Arch system packages remain rolling dependencies.

## Repository layout

| Path | Contents |
| --- | --- |
| [`scripts/`](scripts/) | Standalone installer and runtime verifier |
| [`locks/`](locks/) | ROS source commits and Python tool versions |
| [`docs/`](docs/) | Installation guide and validation scope |
| [`evidence/2026-09-23-arm64/`](evidence/2026-09-23-arm64/) | Compact, unchanged logs from the verified VM run |
| [`tools/check_repository.py`](tools/check_repository.py) | Local and CI integrity checks |

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and validation instructions.

## License

Original project code and documentation are [MIT licensed](LICENSE). Downloaded dependencies retain their own upstream licenses; see [third-party notices](THIRD_PARTY_NOTICES.md).
