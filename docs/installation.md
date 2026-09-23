# ROS 2 Lyrical on Omarchy

This installer compiles **ROS 2 Lyrical ros_base**, its command-line tools, and the upstream C++ and Python demo nodes directly on Omarchy/Arch Linux. It uses native Linux binaries, a workspace-local Python environment, Fast DDS, and a local build of Orocos KDL/PyKDL. RViz, Gazebo, and the full desktop variant are outside this build.

## Install

Run from the cloned repository root, inside Omarchy as your normal user, from a fresh Bash shell without another ROS distribution sourced:

```bash
bash scripts/install-ros2-lyrical.sh --jobs 2
```

The default workspace is `~/ros2_lyrical`. Set a different path with `--workspace /path/to/ros2_lyrical`. Use `--yes` to make pacman noninteractive. The script uses sudo only for system packages, performs a full `pacman -Syu` to avoid a partial Arch upgrade, and leaves shell startup files unchanged. Allow at least 12 GiB free space; 8 GiB RAM and two compiler jobs are the tested target configuration.

For split administrator/user execution:

```bash
sudo bash scripts/install-ros2-lyrical.sh --deps-only --yes
bash scripts/install-ros2-lyrical.sh --skip-system-deps --jobs 2
```

Rerun the same command to resume after a failure. Existing build output is reused. The installer fetches all 106 source checkouts at embedded commit hashes, rejects dirty or mismatched checkouts, and records them in `sources.lock.repos`. It also consumes embedded constraints for the tested Python build tools, including pip, colcon, pybind11, EmPy, and setuptools. System dependencies remain Arch rolling-release packages, with the actual installed versions recorded in `logs/build-environment.txt`.

## Use ROS

```bash
source ~/ros2_lyrical/env.bash
ros2 run demo_nodes_cpp talker
```

In a second terminal:

```bash
source ~/ros2_lyrical/env.bash
ros2 run demo_nodes_py listener
```

Press **Ctrl+C** in each terminal to stop. The environment wrapper loads the matching Python environment, local KDL libraries, and the ROS installation. Source it in every new terminal that needs ROS.

## Run the proof

Keep the two verifier files beside each other in `scripts/`, then run from the repository root:

```bash
bash scripts/verify-ros2-lyrical.sh ~/ros2_lyrical/install ./new-proof
```

The output directory must not already exist. The verifier runs the genuine upstream talker/listener programs in both directions: C++ → Python and Python → C++. A third ROS node independently observes the topic. Each direction must produce at least five identical message payloads in all three logs, with the expected publisher/subscriber endpoints visible in the ROS graph. It checks `ROS_DISTRO=lyrical`, installation prefixes, and Fast DDS middleware, and records package versions. Nodes use a unique namespace and a randomly selected localhost discovery domain, and are stopped automatically after the test.

Read `report.json`, `cpp-to-python/`, and `python-to-cpp/` in the evidence directory. A successful exit alone is not a substitute for the saved `PASS` report and matching message logs.

## Scope and source references

Omarchy/Arch is outside the [official Lyrical platform list](https://github.com/ros2/ros2_documentation/blob/rolling/source/Get-Started/Releases/lyrical/supported-platforms.rst). This is a source-build integration, not an official Arch binary distribution. The script supports the `x86_64` and `aarch64` architecture names; validation on one architecture does not establish a test result on the other.

- [Official ROS 2 release manifest, pinned revision](https://github.com/ros2/ros2/blob/8577ad203d60bdd0a49eba7048709d47efb73b97/ros2.repos)
- [ROS variants](https://github.com/ros2/variants/tree/0.13.0)
- [Orocos KDL/PyKDL 1.5.4](https://github.com/orocos/orocos_kinematics_dynamics/tree/1.5.4)
- [Official Lyrical demo sources](https://github.com/ros2/demos/tree/lyrical)

Fast DDS is the selected middleware. Connext, Cyclone DDS, and Zenoh middleware are not enabled; LTTng tracing and package unit-test builds are disabled. Optional ament lint and documentation executables are not provisioned by this installer. The included runtime proof exercises communication, Python/C++ message bindings, discovery, and the built installation. It does not test physical robots, drivers, GUI applications, or every ROS package API.

## Arch compatibility changes

- Orocos KDL and PyKDL 1.5.4 are compiled into the workspace dependency prefix.
- Python tooling uses a venv and tested constraints; system Python packages remain managed by pacman.
- Fast DDS 3.6.2's bundled SQLite 3.47.2 fails GCC 16's `-Werror=stringop-overflow` check. An external CMake hook links the Arch system SQLite library and uses its header for the persistence implementation. The bundled SQLite C file is excluded from compilation. DDS persistence remains enabled, and compiler warnings are still treated as errors. The ROS source checkouts stay unchanged.
- `CMAKE_POLICY_VERSION_MINIMUM=3.5` accommodates older vendored CMake projects on Arch's CMake 4.

The talker/listener proof does not exercise DDS persistence. Link/configuration evidence establishes that the persistence implementation is enabled and uses system SQLite.
