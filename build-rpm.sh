#!/usr/bin/env bash
set -e

echo "==> Preparing RPM build environment..."
sudo dnf install -y rpm-build rpmdevtools

RPMBUILD_DIR="${HOME}/rpmbuild"
rpmdev-setuptree 2>/dev/null || mkdir -p "${RPMBUILD_DIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

echo "==> Copying spec and sources to rpmbuild tree..."
cp kwin-scroll-daemon.spec "${RPMBUILD_DIR}/SPECS/"

cp kwin_scroll_daemon.py "${RPMBUILD_DIR}/SOURCES/"
cp kwin-scroll-rules.json "${RPMBUILD_DIR}/SOURCES/"
cp kwin-scroll-daemon.service "${RPMBUILD_DIR}/SOURCES/"
cp metadata.json "${RPMBUILD_DIR}/SOURCES/"
cp main.js "${RPMBUILD_DIR}/SOURCES/"

echo "==> Building noarch RPM..."
rpmbuild -ba "${RPMBUILD_DIR}/SPECS/kwin-scroll-daemon.spec"

echo ""
echo "===================================================================="
echo "RPM built successfully!"
echo "Find it at:"
ls -lh "${RPMBUILD_DIR}/RPMS/noarch"/kwin-scroll-daemon*.rpm
echo ""
echo "To install with dnf:"
echo "  sudo dnf install -y ${RPMBUILD_DIR}/RPMS/noarch/kwin-scroll-daemon*.rpm"
echo "===================================================================="
