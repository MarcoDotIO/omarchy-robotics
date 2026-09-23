#!/usr/bin/env bash
# Native ROS 2 Lyrical source build for Omarchy / Arch Linux (x86_64 or aarch64).
set -Eeuo pipefail

WORKSPACE=${ROS_LYRICAL_WS:-"${HOME:-/root}/ros2_lyrical"}
JOBS=${ROS_BUILD_JOBS:-2}
YES=0
SKIP_DEPS=0
DEPS_ONLY=0
FETCH_ONLY=0
while (($#)); do
  case "$1" in
    --workspace) WORKSPACE=${2:?missing workspace}; shift 2 ;;
    --jobs) JOBS=${2:?missing jobs}; shift 2 ;;
    --yes) YES=1; shift ;;
    --skip-system-deps) SKIP_DEPS=1; shift ;;
    --deps-only) DEPS_ONLY=1; shift ;;
    --fetch-only) FETCH_ONLY=1; shift ;;
    -h|--help)
      cat <<'HELP'
Usage: bash install-ros2-lyrical.sh [--workspace PATH] [--jobs N] [--yes]
Builds native Lyrical ros_base, C++/Python demos and their dependencies.
Installs Arch dependencies with a full pacman -Syu (never a partial upgrade).
Builds as your user in ~/ros2_lyrical. Does not change shell startup files.
--yes                 Make pacman noninteractive.
--deps-only           Only install system dependencies; root is allowed here.
--skip-system-deps    Build after an administrator has installed dependencies.
--fetch-only          Prepare Python tools and import sources, then stop.
--jobs N              Concurrent compiler jobs (default 2; 8 GB RAM recommended).
HELP
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || { echo 'Jobs must be a positive integer' >&2; exit 2; }
[[ $(uname -s) == Linux ]] || { echo 'Run this script inside Omarchy/Arch Linux, not macOS.' >&2; exit 2; }
source /etc/os-release
[[ ${ID:-} == arch || ${ID:-} == archarm || " ${ID_LIKE:-} " == *' arch '* ]] || {
  echo 'This installer requires an Arch-based system with pacman.' >&2; exit 2;
}
case $(uname -m) in x86_64|aarch64) ;; *) echo 'Supported architectures: x86_64, aarch64' >&2; exit 2 ;; esac
[[ -z ${ROS_DISTRO:-} ]] || { echo 'Use a fresh shell without another ROS installation sourced.' >&2; exit 2; }
(( EUID != 0 || DEPS_ONLY )) || { echo 'Run builds as a normal user; use --deps-only for root dependency installation.' >&2; exit 2; }

if (( ! SKIP_DEPS )); then
  echo 'Installing build dependencies and applying the Arch full-system upgrade...'
  pacman_args=(-Syu --needed)
  (( ! YES )) || pacman_args+=(--noconfirm)
  packages=(base-devel cmake ninja git curl python python-pip python-numpy
    python-yaml python-setuptools python-packaging python-lxml python-cryptography
    eigen asio tinyxml2 yaml-cpp libyaml openssl sqlite zstd lz4 zlib bzip2
    libunwind pkgconf bullet graphviz spdlog fzf)
  if (( EUID == 0 )); then pacman "${pacman_args[@]}" "${packages[@]}"
  else sudo pacman "${pacman_args[@]}" "${packages[@]}"; fi
fi
(( ! DEPS_ONLY )) || exit 0

mkdir -p "$WORKSPACE"
WORKSPACE=$(cd "$WORKSPACE" && pwd -P)
[[ $WORKSPACE != *' '* ]] || { echo 'ROS workspace paths must not contain spaces.' >&2; exit 2; }
cd "$WORKSPACE"
mkdir -p logs src
exec > >(tee -a "logs/installer-$(date -u +%Y%m%dT%H%M%SZ).log") 2>&1
trap 'echo "FAILED at line $LINENO. See $WORKSPACE/logs and $WORKSPACE/log/latest_build." >&2' ERR
exec 9>"$WORKSPACE/.installer.lock"
flock -n 9 || { echo 'Another installer is using this workspace.' >&2; exit 1; }
if [[ ! -e .omarchy-lyrical-workspace ]]; then
  [[ -z $(find src -mindepth 1 -maxdepth 1 -print -quit) ]] || {
    echo 'Refusing to import into an existing unrelated source workspace.' >&2; exit 1;
  }
  touch .omarchy-lyrical-workspace
fi
available_kb=$(df -Pk . | awk 'NR==2 {print $4}')
(( available_kb >= 12*1024*1024 )) || { echo 'At least 12 GiB free disk space is required.' >&2; exit 1; }
python -m venv --system-site-packages .venv
source .venv/bin/activate
python -m pip install --upgrade 'pip==26.2.1'
cat > python-tools.constraints.txt <<'PYTHON_TOOLS'
argcomplete==3.7.2
catkin-pkg==1.1.1
colcon-argcomplete==0.3.3
colcon-bash==0.5.0
colcon-cd==0.1.1
colcon-cmake==0.2.30
colcon-common-extensions==0.3.0
colcon-core==0.21.3
colcon-defaults==0.2.9
colcon-devtools==0.3.0
colcon-library-path==0.2.1
colcon-metadata==0.3.1
colcon-notification==0.3.3
colcon-output==0.2.15
colcon-package-information==0.4.1
colcon-package-selection==0.2.10
colcon-parallel-executor==0.4.0
colcon-pkg-config==0.1.0
colcon-powershell==0.5.0
colcon-python-setup-py==0.2.9
colcon-recursive-crawl==0.2.3
colcon-ros==0.5.0
colcon-test-result==0.3.8
colcon-zsh==0.5.0
coverage==7.16.1
distlib==0.4.3
docutils==0.23
empy==4.2.1
iniconfig==2.3.0
netifaces==0.11.0
notify2==0.3.1
pluggy==1.6.0
psutil==7.2.2
pybind11==3.1.0
Pygments==2.21.0
pyparsing==3.3.3
pytest==9.1.1
pytest-cov==7.1.0
pytest-repeat==0.9.4
pytest-rerunfailures==16.7
python-dateutil==2.9.0.post0
rosdep==0.27.0
rosdistro==1.1.0
rospkg==1.6.3
setuptools==79.0.1
six==1.17.0
vcstool==0.3.0
lark==1.3.1
typing_extensions==4.16.0
wheel==0.48.0
pip==26.2.1
osrf-pycommon==2.0.2
PYTHON_TOOLS
python -m pip install -c python-tools.constraints.txt 'setuptools<81' wheel colcon-common-extensions vcstool rosdep \
  catkin-pkg empy lark pyparsing argcomplete psutil netifaces pybind11 typing_extensions osrf-pycommon
python -m pip freeze > logs/python-requirements.txt

# Official release manifest pinned to an immutable ros2/ros2 commit.
MANIFEST_COMMIT=8577ad203d60bdd0a49eba7048709d47efb73b97
MANIFEST_SHA256=7a0c854b19c27aa7b3ff8043a50b9104da5cda3228783d0a57a0fe8d2c36c99c
curl --fail --location --retry 3 \
  "https://raw.githubusercontent.com/ros2/ros2/$MANIFEST_COMMIT/ros2.repos" -o ros2-upstream.repos
echo "$MANIFEST_SHA256  ros2-upstream.repos" | sha256sum --check --status
python - <<'PY'
from pathlib import Path
import yaml
manifest = yaml.safe_load(Path('ros2-upstream.repos').read_text())
manifest['repositories']['ros2/variants'] = {
    'type': 'git', 'url': 'https://github.com/ros2/variants.git',
    'version': '4f88faf30639b5219db2582f7eba34933cbce346'}
pinned_commits = {
    "ament/ament_cmake": "46a63275c1c2ff2383f32d0c378784aafd70e6e2",
    "ament/ament_index": "fec7e400bb2a50f32e1683482bf93da0b480839d",
    "ament/ament_lint": "b43377801cbd56883fd1b70b1db04454b9656157",
    "ament/ament_package": "98089783110f7606a90e8ef9786719c3d0cd32f9",
    "ament/google_benchmark_vendor": "9c4200c9f567bbfb9c24c563236df48b16e8c6c3",
    "ament/googletest": "359b3f059a7545e66360f4fac7a60309f91662ab",
    "ament/uncrustify_vendor": "a2a8e43c8bdd70f1005443f89f2e2c531cb493ab",
    "eProsima/Fast-CDR": "d7219391608ae8cd7971e761206dc020098bacb3",
    "eProsima/Fast-DDS": "39303846fb8534ef69fa65f9fa4bcc9e6a7c995a",
    "eProsima/foonathan_memory_vendor": "347cb67581e51273a612780eb256a3c134c10bae",
    "eclipse-cyclonedds/cyclonedds": "e54e991f75a3e67f8e628da3171122e36ea5b872",
    "eclipse-iceoryx/iceoryx": "35311bfe5338392d65b18f148de70b803f6fc48e",
    "gazebo-release/gz_cmake_vendor": "9a8db7342bcf9d6287f2c997123cd22b9844241a",
    "gazebo-release/gz_math_vendor": "2e37193cf782e5b391303b9a80342d91e71e08c0",
    "gazebo-release/gz_utils_vendor": "9e6f3f4baa0ba9421f69b9326d5061fa5e489dec",
    "osrf/osrf_testing_tools_cpp": "8238d9a5dadcfb4a2c74aa3f0629f5fcbe177002",
    "ros-perception/image_common": "334c032cf2ba3d3818544315b3327c7ce25100f2",
    "ros-perception/laser_geometry": "968219ea2e65995fc5594e94d3aa1ce262936d5f",
    "ros-perception/point_cloud_transport": "3d0b36d11091c91e3ff55beb93240fef5be51e47",
    "ros-planning/navigation_msgs": "b6df4fdf0f0ab27824f09d89e4bba563403206e4",
    "ros-tooling/keyboard_handler": "e191305c350318a5c014dee78489307383474114",
    "ros-tooling/libstatistics_collector": "7ce1d52494c52ba20fc38ad4f72d006d40346135",
    "ros-visualization/interactive_markers": "2faa7662a27428776557de0246398042cf48478e",
    "ros-visualization/python_qt_binding": "a5bb28ed4a0055c452d576486a7f6ba3a320ec84",
    "ros-visualization/qt_gui_core": "7eb733fce056ea46deb51bad6f504cee625f0c64",
    "ros-visualization/rqt": "f3a34c1ec8f150367202df99f5e29dc8b9252c41",
    "ros-visualization/rqt_action": "143f00b8a870dde47e91317b7668df9b0cc4aa75",
    "ros-visualization/rqt_bag": "d3d0eb5d4ae5797a13ddc31934f8f3985fd83ee5",
    "ros-visualization/rqt_console": "0a2c932e341d653115a3163383d211b8092a5b30",
    "ros-visualization/rqt_graph": "c4967846be7965a2b2b3bd4f1ab37c65d0feaa08",
    "ros-visualization/rqt_msg": "c6ea9f1dc47468dc931b70269ede63514ca496b2",
    "ros-visualization/rqt_plot": "2492c25114c83deb5a7fda47b7a210cb8fab465b",
    "ros-visualization/rqt_publisher": "4e8e454577af163b2798d095ee294b493b19b0f0",
    "ros-visualization/rqt_py_console": "24cd83b84d41bef65c50e26cbf43abf6ccb2bcbf",
    "ros-visualization/rqt_reconfigure": "991037fd78d5d9086e80f55e9f0babfe71e90199",
    "ros-visualization/rqt_service_caller": "9befa336dadc778c69376c869da70251ef7477d8",
    "ros-visualization/rqt_shell": "e301132a8f46d6fb32e13cbeb18373a94fc8c86d",
    "ros-visualization/rqt_srv": "c0f224f783c78776e4f21b18a32f39e0ac10517a",
    "ros-visualization/rqt_topic": "a75d2560b9d92735e9d67074ac8428ef1a241e99",
    "ros-visualization/tango_icons_vendor": "946c3b732f24c9ca2254d66721f9605b4fa70bf1",
    "ros/class_loader": "86d1053cbdfdb80d3f4fd631ea1e4b148ce25c41",
    "ros/kdl_parser": "92cbd6e5d6b2d41dc360e102bc71b00a0f20e3f2",
    "ros/pluginlib": "3f1889cd34a2c989cbcae141cc9e6b24471c2e37",
    "ros/resource_retriever": "09d43b14b458eca076571e4b6a6e18b1619eed98",
    "ros/robot_state_publisher": "e069e9cfed8d0f7fb1b5b813e1e42ec6a3a62e93",
    "ros/ros_environment": "4deb7a5f56274e7069b15491e5b8cc34c0a2c0e6",
    "ros/ros_tutorials": "578a96d76f981351caa8fb5a026b61aec9649aaf",
    "ros/urdfdom": "6d8d623326a503bd22558b9f4080d4a7c69abedb",
    "ros/urdfdom_headers": "9152266da22072e56ace2256509ef4c34917e7ee",
    "ros2-rust/rosidl_rust": "4adee4f29987c9dcd239a1bd3d99a83f46bbaa3f",
    "ros2/ament_cmake_ros": "c8fac25b5d47888f21aa3ea6f81367862756c942",
    "ros2/common_interfaces": "6099c3b82abe20da50bf410e8173127ea1d83d30",
    "ros2/console_bridge_vendor": "1a1650a2cdc1e386d496aff42bb3aca537075763",
    "ros2/demos": "f9d9ddf21a0b7bc4f070a917783fac08f93c9f98",
    "ros2/eigen3_cmake_module": "72e9fbb13a0d20b9452eff079a0701042ecd5915",
    "ros2/example_interfaces": "e4f46c5762e433a72b2496bb23b0375ecfc06d1e",
    "ros2/examples": "c6941ce96daf1c53212f0f0428a1fba56c35b7b0",
    "ros2/geometry2": "0b06614aaf3a50ddd1298cb0d95224b0e3821b25",
    "ros2/launch": "de12ecc7a03008bff771760d1b4c55c2175508c3",
    "ros2/launch_ros": "b1f3c350b3d485a703ca64aec6a7d46d89f05603",
    "ros2/libyaml_vendor": "78a2eb793c0aefb399f0fc7e9882524868b117c1",
    "ros2/message_filters": "215180744ff5e99803f508101370a9ad71bf7e5d",
    "ros2/mimick_vendor": "a1d9ddd67a5973470646744f122d74c108bb3352",
    "ros2/performance_test_fixture": "9d8bd9ebafcba8bbea9a2fc1d36aeafabe83728b",
    "ros2/rcl": "38d18f5148a4dda621fdb1ac5d89deee6f19c783",
    "ros2/rcl_interfaces": "b90e36e4adf5ed878efa2f365a84798f782618cd",
    "ros2/rcl_logging": "904c0971bd0b3581094af853b76b56304915248e",
    "ros2/rclcpp": "9a1e199abeea7ac07363d5c890bdf9078d2d3b3d",
    "ros2/rclpy": "02b36e689a381380017422cbc053cdc0207d6d12",
    "ros2/rcpputils": "b8775ec03b9412789b34358c738b0e87c53e1b31",
    "ros2/rcutils": "71406a100612c0c2bd6c0c1a8babe26e765d1499",
    "ros2/realtime_support": "6f0295dd3ca60295d5d07b2f7a72e6f77d505127",
    "ros2/resource_retriever_service": "17bd37f48cc094a60a2872f7fab85a80c052d965",
    "ros2/rmw": "2fd339ba950dc70c2f594e0c3fd69d8a1b217d63",
    "ros2/rmw_connextdds": "d77387699f4c602e1169725b57ad5a850aefd1a9",
    "ros2/rmw_cyclonedds": "74e8047eb717953b31155323bfe137e81caa423e",
    "ros2/rmw_dds_common": "2f00e6e9208e925d61330ea92f857b2e67d595ab",
    "ros2/rmw_fastrtps": "e175f84a861e8a66fb53035d27d34bc3212c161e",
    "ros2/rmw_implementation": "b2083abba8c13900acf55f1dbdb8447757ff2b75",
    "ros2/rmw_zenoh": "4e17ccfb9e114c87ac87b802e705b60e283b4115",
    "ros2/ros2_tracing": "24c3dea0fcee6f1fd0eb5244c6e1ea390dd479ac",
    "ros2/ros2cli": "aff7506d5d08ab4b67e14054588762fbea035445",
    "ros2/ros2cli_common_extensions": "4625537997005f6b59d90dd9e10d5dc1b11bb46c",
    "ros2/ros_testing": "5364b5e9a9537e5aee4254857bf1f5c522715c1a",
    "ros2/rosbag2": "059220ba38fae58d190d778b890bd9b6b79513e2",
    "ros2/rosidl": "024f0b9636d716b9756c25ade0b6d7b15bde18e9",
    "ros2/rosidl_core": "2e34a7cb22db268e2bfac06eb8b47615818051ad",
    "ros2/rosidl_dds": "772632eb729ab48f368a0862659224be80caf56b",
    "ros2/rosidl_defaults": "1c730458cbee50e2941f67e441e0fd5a3d3c7e6b",
    "ros2/rosidl_dynamic_typesupport": "f9ee0542b725244ba5633cb3c03d2f9cc0da0064",
    "ros2/rosidl_dynamic_typesupport_fastrtps": "de01f56ccbf80851b5460a3ca169b4ca71c58b48",
    "ros2/rosidl_python": "a7e54557a4f6a910f1c4dfa9cf590e36f8828413",
    "ros2/rosidl_runtime_py": "23443e3ed8892c2205727ec3d725761f346b7ec3",
    "ros2/rosidl_typesupport": "f21f4d6cbb76e0da104bd8fdd093fc6a3ade59d2",
    "ros2/rosidl_typesupport_fastrtps": "014b856d79b46802c81dd244820198e1d846b486",
    "ros2/rpyutils": "961945ecfeddba87b86c8c2a9f449d49678b7456",
    "ros2/rviz": "baab61a68bc089217dfaa4f270276dc7a30268b1",
    "ros2/spdlog_vendor": "233537fc15af24bc653fcbf7cad64e81a593cc36",
    "ros2/sros2": "2b6dc78ea941f1065fa05ff92d5a753276603aeb",
    "ros2/system_tests": "15603eeb876a8010488803d0ed33023b2406e0e0",
    "ros2/test_interface_files": "a565a8927962e5bcbd5667b884a0f0652568c177",
    "ros2/tlsf": "8179f2cd2a5018aaf752ce11a0cfa50694b0370c",
    "ros2/unique_identifier_msgs": "b4779af6b3d3c45e710802a0e7f86113da281ae8",
    "ros2/urdf": "44689976498b52798971850061f2e2c8d8b25661",
    "ros2/variants": "c72de4fb5b6ecb908338e4780c570c8d7a5dc30c",
    "ros2/yaml_cpp_vendor": "47d916a33edf04cae857abcc651b36f44a442bd4"
}
if set(manifest['repositories']) != set(pinned_commits):
    raise SystemExit('Manifest repositories do not match the tested source pins')
for name, repo in manifest['repositories'].items():
    repo['version'] = pinned_commits[name]
Path('ros2.repos').write_text(yaml.safe_dump(manifest, sort_keys=False))
PY
vcs import --shallow --workers "$JOBS" src < ros2.repos
python - <<'PY'
import subprocess
from pathlib import Path
import yaml
manifest = yaml.safe_load(Path('ros2.repos').read_text())
for name, repo in manifest['repositories'].items():
    path = Path('src') / name
    dirty = subprocess.check_output(['git', '-C', str(path), 'status', '--porcelain'], text=True)
    if dirty:
        raise SystemExit(f'Refusing to build modified source in {path}:\n{dirty}')
    head = subprocess.check_output(['git', '-C', str(path), 'rev-parse', 'HEAD'], text=True).strip()
    expected = repo['version']
    if head != expected:
        raise SystemExit(f'Wrong checkout in {path}: {head}, expected pinned commit {expected}')
    repo['version'] = head
Path('sources.lock.repos').write_text(yaml.safe_dump(manifest, sort_keys=False))
PY
(( ! FETCH_ONLY )) || { echo "Sources prepared in $WORKSPACE"; exit 0; }

# Build the native kinematics dependency unavailable in the Arch ARM repositories.
KDL_REVISION=84b086838dea2b1132064517a61017d30945f1d3 # upstream tag 1.5.4
KDL_SOURCE="$WORKSPACE/dependency-src/orocos_kinematics_dynamics"
KDL_PREFIX="$WORKSPACE/dependencies"
KDL_PYTHON="$WORKSPACE/.venv/bin/python"
KDL_PYTHON_VERSION="$($KDL_PYTHON -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
KDL_PYTHON_INSTALL="$KDL_PREFIX/lib/python$KDL_PYTHON_VERSION/site-packages"

mkdir -p "$WORKSPACE/dependency-src" "$WORKSPACE/dependency-build" "$KDL_PREFIX"
if [[ ! -d "$KDL_SOURCE/.git" ]]; then
  [[ ! -e "$KDL_SOURCE" ]] || { echo "Refusing to replace existing non-Git directory: $KDL_SOURCE" >&2; exit 2; }
  git clone --depth 1 --branch 1.5.4 https://github.com/orocos/orocos_kinematics_dynamics.git "$KDL_SOURCE"
fi
[[ "$(git -C "$KDL_SOURCE" rev-parse HEAD)" == "$KDL_REVISION" ]] || {
  echo "Unexpected KDL checkout; expected $KDL_REVISION at $KDL_SOURCE" >&2
  exit 2
}
[[ -z "$(git -C "$KDL_SOURCE" status --porcelain)" ]] || {
  echo "Refusing to build modified KDL source: $KDL_SOURCE" >&2
  exit 2
}

cmake -S "$KDL_SOURCE/orocos_kdl" -B "$WORKSPACE/dependency-build/orocos_kdl" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$KDL_PREFIX" \
  -DENABLE_TESTS=OFF -DENABLE_EXAMPLES=OFF
cmake --build "$WORKSPACE/dependency-build/orocos_kdl" --parallel "$JOBS"
cmake --install "$WORKSPACE/dependency-build/orocos_kdl"

# Arch's pybind11 >= 3.0 supports Python 3.14. Require the installed package so
# this cannot silently select the older uninitialized upstream submodule.
KDL_PYBIND_DIR="$(python -m pybind11 --cmakedir)"
[[ -f "$KDL_PYBIND_DIR/pybind11Config.cmake" ]] || {
  echo 'The tooling venv must provide pybind11.' >&2
  exit 2
}
cmake -S "$KDL_SOURCE/python_orocos_kdl" -B "$WORKSPACE/dependency-build/python_orocos_kdl" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$KDL_PREFIX" \
  -DCMAKE_PREFIX_PATH="$KDL_PREFIX${CMAKE_PREFIX_PATH:+;$CMAKE_PREFIX_PATH}" \
  -DPython3_EXECUTABLE="$KDL_PYTHON" \
  -Dpybind11_DIR="$KDL_PYBIND_DIR" \
  -DPYTHON_SITE_PACKAGES_INSTALL_DIR="$KDL_PYTHON_INSTALL"
cmake --build "$WORKSPACE/dependency-build/python_orocos_kdl" --parallel "$JOBS"
cmake --install "$WORKSPACE/dependency-build/python_orocos_kdl"

LD_LIBRARY_PATH="$KDL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  PYTHONPATH="$KDL_PYTHON_INSTALL${PYTHONPATH:+:$PYTHONPATH}" \
  "$KDL_PYTHON" -c 'import PyKDL; assert PyKDL.Vector(1, 2, 3).Norm() > 3; print("OROCOS_KDL_PYKDL_IMPORT_OK")'
printf '%s\n' "revision=$KDL_REVISION" "python=$KDL_PYTHON_VERSION" "prefix=$KDL_PREFIX" > "$KDL_PREFIX/orocos-kdl-build.txt"

export CMAKE_PREFIX_PATH="$KDL_PREFIX${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$KDL_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export PYTHONPATH="$KDL_PYTHON_INSTALL${PYTHONPATH:+:$PYTHONPATH}"

export ROS_DISTRO=lyrical
export ROS_VERSION=2
export ROS_PYTHON_VERSION=3
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export CMAKE_BUILD_PARALLEL_LEVEL=$JOBS
export MAKEFLAGS="-j$JOBS"
# Fast DDS 3.6.2 bundles SQLite 3.47.2, whose amalgamation fails GCC 16's
# stringop-overflow check under -Werror. Use Arch's maintained SQLite instead.
# Keep warnings-as-errors and DDS persistence enabled; leave source checkouts clean.
mkdir -p compat
cat > compat/fastdds-system-sqlite.cmake <<'CMAKE_SQLITE'
function(omarchy_fastdds_system_sqlite)
  if(NOT TARGET fastdds OR NOT SQLITE3_SUPPORT)
    message(FATAL_ERROR "Expected Fast DDS with SQLite persistence enabled")
  endif()
  find_package(SQLite3 3.47 REQUIRED)
  get_target_property(fastdds_source_directory fastdds SOURCE_DIR)
  set_source_files_properties(
    "${fastdds_source_directory}/rtps/persistence/sqlite3.c"
    DIRECTORY "${fastdds_source_directory}"
    PROPERTIES HEADER_FILE_ONLY TRUE)
  set(sqlite_shim "${CMAKE_BINARY_DIR}/omarchy-system-sqlite")
  file(MAKE_DIRECTORY "${sqlite_shim}/rtps/persistence")
  file(WRITE "${sqlite_shim}/rtps/persistence/sqlite3.h"
    "#pragma once\n#include <sqlite3.h>\n")
  set_property(SOURCE
    "${fastdds_source_directory}/rtps/persistence/SQLite3PersistenceService.cpp"
    DIRECTORY "${fastdds_source_directory}"
    APPEND PROPERTY INCLUDE_DIRECTORIES "${sqlite_shim}")
  if(TARGET SQLite3::SQLite3)
    target_link_libraries(fastdds PRIVATE SQLite3::SQLite3)
  else()
    target_link_libraries(fastdds PRIVATE SQLite::SQLite3)
  endif()
  message(STATUS "Omarchy: Fast DDS uses system SQLite ${SQLite3_VERSION}")
endfunction()
cmake_language(DEFER CALL omarchy_fastdds_system_sqlite)
CMAKE_SQLITE

# Connext needs a separately licensed SDK; Cyclone and Zenoh are optional RMWs.
# Keep source-vendored Fast DDS and Fast CDR to match the Lyrical release.
colcon build --base-paths src --merge-install --executor sequential \
  --packages-up-to ros_base demo_nodes_cpp demo_nodes_py \
  --packages-ignore rmw_connextdds rmw_cyclonedds_cpp rmw_zenoh_cpp \
    zenoh_cpp_vendor cyclonedds \
  --event-handlers console_cohesion+ \
  --cmake-args -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DTRACETOOLS_DISABLED=ON \
    -DCMAKE_PROJECT_fastdds_INCLUDE="$WORKSPACE/compat/fastdds-system-sqlite.cmake" \
    -Dpybind11_DIR="$KDL_PYBIND_DIR" \
    -DRMW_IMPLEMENTATION=rmw_fastrtps_cpp \
    -DPython3_EXECUTABLE="$WORKSPACE/.venv/bin/python"

cat > env.bash <<EOF
# Source this in a fresh Bash shell before using this ROS installation.
source "$WORKSPACE/.venv/bin/activate"
export CMAKE_PREFIX_PATH="$KDL_PREFIX\${CMAKE_PREFIX_PATH:+:\$CMAKE_PREFIX_PATH}"
export LD_LIBRARY_PATH="$KDL_PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PYTHONPATH="$KDL_PYTHON_INSTALL\${PYTHONPATH:+:\$PYTHONPATH}"
source "$WORKSPACE/install/setup.bash"
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
EOF
{
  date -u --iso-8601=seconds
  uname -a
  cat /etc/os-release
  [[ ! -f /usr/share/omarchy/version ]] || cat /usr/share/omarchy/version
  gcc --version | head -1
  cmake --version | head -1
  python --version
  pacman -Q
} > logs/build-environment.txt
printf '\nBUILD COMPLETE. In a fresh shell:\n  source %q/env.bash\n  ros2 run demo_nodes_cpp talker\n' "$WORKSPACE"
