#!/bin/bash

set -e
set -o pipefail

CAMERA_REPO="$PWD"

CAMERA_CONFIG="${CAMERA_REPO}/camera-config"
CAMERA_MAKE="iGET"
CAMERA_MODEL="C5PT"
CAMERA_SOC="T41LQ"
CAMERA_SENSOR="unknown"
CAMERA_PHY="JL1101"
CAMERA=$(echo "${CAMERA_MAKE}_${CAMERA_MODEL}_${CAMERA_SOC}_${CAMERA_SENSOR}_${CAMERA_PHY}" | awk '{print tolower($0)}' | tr ' ' '-')

THINGINO_REPO="${CAMERA_REPO}/thingino-firmware"
THINGINO_GIT="git@github.com:LukasMojzis/thingino-firmware"
THINGINO_BRANCH="stable"
THINGINO_CAMERA="${THINGINO_REPO}/configs/cameras/${CAMERA}"

UBOOT_REPO="${CAMERA_REPO}/u-boot"
UBOOT_GIT="git@github.com:LukasMojzis/ingenic-u-boot-xburst2"
UBOOT_BRANCH="t41"

echo "Building ${CAMERA}"

if [ -d "${THINGINO_REPO}" ]; then
  echo -n "Updating thingino-firmware.. "
  cd "${THINGINO_REPO}"
  git checkout "${THINGINO_BRANCH}" -q
  git pull -q
else
  echo -n "Fetching thingino-firmware.. "
  git clone "${THINGINO_GIT}" "${THINGINO_REPO}" -b "${THINGINO_BRANCH}" -q
fi
echo "done."

echo -n "Configuring thingino-firmware.. "
THINGINO_UBOOT_OVERRIDE_SRCDIR='$(BR2_EXTERNAL)/overrides/thingino-uboot'
grep "THINGINO_UBOOT_OVERRIDE_SRCDIR = ${THINGINO_UBOOT_OVERRIDE_SRCDIR}" "${THINGINO_REPO}/local.mk" &> /dev/null || \
echo "THINGINO_UBOOT_OVERRIDE_SRCDIR = ${THINGINO_UBOOT_OVERRIDE_SRCDIR}" >> "${THINGINO_REPO}/local.mk"
THINGINO_UBOOT="${THINGINO_REPO}/${THINGINO_UBOOT_OVERRIDE_SRCDIR//\$\(BR2_EXTERNAL\)\//}"
echo "done."

if [ -d "${UBOOT_REPO}" ]; then
  echo -n "Updating u-boot.. "
  cd "${UBOOT_REPO}"
  git checkout "${UBOOT_BRANCH}" -q
  git pull -q
else
  echo -n "Fetching u-boot.. "
  git clone "${UBOOT_GIT}" "${UBOOT_REPO}" -b "${UBOOT_BRANCH}" -q
fi
echo "done."

echo -n "Syncing config files.. "
mkdir -p "${THINGINO_CAMERA}"
rsync -a --delete "${CAMERA_CONFIG}/" "${THINGINO_CAMERA}" --exclude="defconfig" --exclude="uenv.txt" && \
rsync -a --delete "${CAMERA_CONFIG}/defconfig" "${THINGINO_CAMERA}/${CAMERA}_defconfig" && \
rsync -a --delete "${CAMERA_CONFIG}/uenv.txt" "${THINGINO_CAMERA}/${CAMERA}.uenv.txt"
echo "done."

echo -n "Syncing u-boot files.. "
mkdir -p "${THINGINO_UBOOT}"
rsync -a --delete "${UBOOT_REPO}/" "${THINGINO_UBOOT}"
eval rm "${THINGINO_REPO}/output/${THINGINO_BRANCH}/${CAMERA}-*/build/thingino-uboot-custom" -rf
echo "done."

echo "Starting build process.."
CAMERA="${CAMERA}" "${THINGINO_REPO}/docker-build.sh" "$@"

OUT_FIRMWARE=$(eval ls "${THINGINO_REPO}/output/stable/${CAMERA}-*/images/thingino-${CAMERA}.bin" | tail -1)
OUT_UBOOTENV=$(eval ls "${THINGINO_REPO}/output/stable/${CAMERA}-*/images/u-boot-env.bin" | tail -1)


echo -n "Patching firmware file.. "
dd \
  if="${OUT_UBOOTENV}" \
  of="${OUT_FIRMWARE}" \
  seek=262144 bs=1 count=32768 conv=notrunc status=none
echo "done."

echo "printenv:"
dd \
  if="${OUT_FIRMWARE}" \
  skip=262144 bs=1 count=32768 status=none | strings

echo "Patched firmware: ${OUT_FIRMWARE}"
