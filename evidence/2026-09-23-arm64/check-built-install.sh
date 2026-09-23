#!/usr/bin/env bash
set -eo pipefail
ws=/home/omarchy/ros2_lyrical
source "$ws/env.bash"
echo 'ROS_NATIVE_INSTALL_CHECK'
date -u --iso-8601=seconds
uname -a
printf 'ROS_DISTRO=%s\nROS_VERSION=%s\nRMW_IMPLEMENTATION=%s\n' "$ROS_DISTRO" "$ROS_VERSION" "$RMW_IMPLEMENTATION"
python - <<'PY'
import importlib
for name in ('rclpy', 'launch', 'launch_ros', 'rosbag2_py', 'tf2_ros', 'PyKDL', 'osrf_pycommon'):
    module = importlib.import_module(name)
    print('IMPORT_OK', name, getattr(module, '__file__', '(namespace)'))
import PyKDL
assert abs(PyKDL.Vector(3, 4, 0).Norm() - 5) < 1e-9
PY
ros2 --help >/dev/null
ros2 launch --help >/dev/null
ros2 bag --help >/dev/null
echo ROS_CLI_HELP_OK
file "$ws/install/lib/demo_nodes_cpp/talker"
readelf -d "$ws/install/lib/libfastdds.so" | grep 'NEEDED.*libsqlite3'
grep '^#define HAVE_SQLITE3 1' "$ws/build/fastdds/include/fastdds/config.hpp"
grep -oE '[^ ]*sqlite3.h' "$ws/build/fastdds/src/cpp/CMakeFiles/fastdds.dir/rtps/persistence/SQLite3PersistenceService.cpp.o.d"
grep -q '/usr/include/sqlite3.h' "$ws/build/fastdds/src/cpp/CMakeFiles/fastdds.dir/rtps/persistence/SQLite3PersistenceService.cpp.o.d"
if grep -q 'sqlite3.c.o' "$ws/build/fastdds/src/cpp/CMakeFiles/fastdds.dir/link.txt"; then
  echo 'Unexpected bundled SQLite object in Fast DDS link' >&2; exit 1
fi
echo FASTDDS_SYSTEM_SQLITE_CHECK_OK
git -C "$ws/dependency-src/orocos_kinematics_dynamics" rev-parse HEAD
cat "$ws/dependencies/orocos-kdl-build.txt"
sha256sum /home/omarchy/Projects/ros2-lyrical-installer/install-ros2-lyrical.sh
echo ROS_NATIVE_INSTALL_CHECK_PASS
