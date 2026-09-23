# Contributing

Keep changes focused on native ROS support for Omarchy/Arch. The initial supported build scope is Lyrical ROS Base with Fast DDS and the C++/Python demos.

## Local checks

From the repository root, with Bash and Python 3.11 or newer:

```bash
python3 tools/check_repository.py
```

This check validates syntax, dependency-lock consistency, documentation links, and the integrity of archived proof. It does not install packages or run ROS. GitHub Actions runs the same check on Python 3.11 and 3.14.

## Installer changes

Run builds in a disposable or recoverable Omarchy environment. The installer updates Arch system packages with `pacman -Syu`. Build as an ordinary user; root is supported only for `--deps-only`.

Keep the installer's embedded source revisions and Python constraints synchronized with `locks/`. Preserve the standalone installer: it must not depend on files elsewhere in this repository. Keep the Bash and Python verifier files together.

For a change to installation or runtime verification, build and rerun the genuine demo tests on the claimed platform. Record the exact script hashes, source revisions, toolchain, final build status, and raw node logs. Do not replace measured evidence with illustrative output. The current integrity checks require the shipped scripts to match the archived tested versions; update the evidence and checks together when a new version is validated, preserving the older run's provenance.

## Reporting problems

Include architecture, Omarchy/Arch version, Python/GCC/CMake versions, the command you ran, and the first failed package's log from `~/ros2_lyrical/log/latest_build/`. Remove credentials and unrelated personal information before posting logs.

Keep claims specific: passing repository checks is not a fresh native ROS build, and an ARM64 result does not establish x86_64 or hardware-driver support.

Contributions to original project code are under the repository's MIT license. Third-party dependencies retain their upstream licenses.
