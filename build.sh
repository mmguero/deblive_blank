#!/bin/bash

IMAGE_NAME=deblive
IMAGE_VERSION=1.0.0
IMAGE_DISTRIBUTION=buster

BUILD_ERROR_CODE=1

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit $BUILD_ERROR_CODE
fi

set -e

RUN_PATH="$(pwd)"
SCRIPT_PATH="$( cd -P "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd "$SCRIPT_PATH" >/dev/null 2>&1

WORKDIR="$(mktemp -d -t deblive-XXXXXX)"

function cleanup {
  # unmount any chroot stuff left behind after an error
  (umount -f $(mount | grep chroot | cut -d ' ' -f 3) >/dev/null 2>&1) && sleep 5

  # clean up the temporary build directory
  if ! rm -rf "$WORKDIR"; then
    echo "Failed to remove temporary directory '$WORKDIR'"
    exit $BUILD_ERROR_CODE
  fi
}

if [ -d "$WORKDIR" ]; then
  # ensure that if we "grabbed a lock", we release it (works for clean exit, SIGTERM, and SIGINT/Ctrl-C)
  trap "cleanup" EXIT

  pushd "$WORKDIR" >/dev/null 2>&1
  mkdir -p ./output "./work/$IMAGE_NAME-Live-Build"
  pushd "./work/$IMAGE_NAME-Live-Build" >/dev/null 2>&1
  rsync -a "$SCRIPT_PATH/config" .

  mkdir -p ./config/hooks/live
  pushd ./config/hooks/live
  ln -v -s -f /usr/share/live/build/hooks/live/* ./
  popd >/dev/null 2>&1

  mkdir -p ./config/hooks/normal
  pushd ./config/hooks/normal
  ln -v -s -f /usr/share/live/build/hooks/normal/* ./
  rm -f ./0910-remove-apt-sources-lists
  popd >/dev/null 2>&1

  chown -R root:root *

  # put the date in the grub.cfg entries and configure installation options
  sed -i "s/\(Install Debian Linux\)/\1 $(date +'%Y-%m-%d %H:%M:%S')/g" ./config/includes.binary/boot/grub/grub.cfg
  cp ./config/includes.binary/install/preseed.cfg ./config/includes.binary/install/preseed_crypto.cfg
  cp ./config/includes.binary/install/preseed_base.cfg ./config/includes.binary/install/preseed_minimal.cfg
  sed -i "s@\(partman-auto/method[[:space:]]*string[[:space:]]*\)lvm@\1crypto@g" ./config/includes.binary/install/preseed_crypto.cfg
  sed -i "s@\(/etc/capture_storage_format\)@\1.crypt@g" ./config/includes.binary/install/preseed_crypto.cfg
  sed -i "s@\(/etc/capture_storage_format\)@\1.none@g" ./config/includes.binary/install/preseed_minimal.cfg

  # make sure we install the newer kernel, firmwares, and kernel headers
  echo "linux-image-$(uname -r)" > ./config/package-lists/kernel.list.chroot
  echo "linux-headers-$(uname -r)" >> ./config/package-lists/kernel.list.chroot
  echo "linux-compiler-gcc-8-x86=$(dpkg -s linux-compiler-gcc-8-x86 | grep ^Version: | cut -d' ' -f2)" >> ./config/package-lists/kernel.list.chroot
  echo "linux-kbuild-5.7=$(dpkg -s linux-kbuild-5.7 | grep ^Version: | cut -d' ' -f2)" >> ./config/package-lists/kernel.list.chroot
  echo "firmware-linux=$(dpkg -s firmware-linux | grep ^Version: | cut -d' ' -f2)" >> ./config/package-lists/kernel.list.chroot
  echo "firmware-linux-nonfree=$(dpkg -s firmware-linux-nonfree | grep ^Version: | cut -d' ' -f2)" >> ./config/package-lists/kernel.list.chroot
  echo "firmware-misc-nonfree=$(dpkg -s firmware-misc-nonfree | grep ^Version: | cut -d' ' -f2)" >> ./config/package-lists/kernel.list.chroot
  echo "firmware-amd-graphics=$(dpkg -s firmware-amd-graphics | grep ^Version: | cut -d' ' -f2)" >> ./config/package-lists/kernel.list.chroot

  # and make sure we remove the old stuff when it's all over
  echo "#!/bin/sh" > ./config/hooks/normal/9999-remove-old-kernel-artifacts.hook.chroot
  echo "export LC_ALL=C.UTF-8" >> ./config/hooks/normal/9999-remove-old-kernel-artifacts.hook.chroot
  echo "export LANG=C.UTF-8" >> ./config/hooks/normal/9999-remove-old-kernel-artifacts.hook.chroot
  echo "apt-get -y --purge remove *4.19* || true" >> ./config/hooks/normal/9999-remove-old-kernel-artifacts.hook.chroot
  echo "apt-get -y autoremove" >> ./config/hooks/normal/9999-remove-old-kernel-artifacts.hook.chroot
  echo "apt-get clean" >> ./config/hooks/normal/9999-remove-old-kernel-artifacts.hook.chroot
  chmod +x ./config/hooks/normal/9999-remove-old-kernel-artifacts.hook.chroot

  lb config \
    --image-name "$IMAGE_NAME" \
    --debian-installer live \
    --debian-installer-gui false \
    --debian-installer-distribution $IMAGE_DISTRIBUTION \
    --distribution $IMAGE_DISTRIBUTION \
    --linux-packages "linux-image-$(uname -r | sed 's/-amd64$//')" \
    --architectures amd64 \
    --binary-images iso-hybrid \
    --bootloaders "syslinux,grub-efi" \
    --memtest none \
    --chroot-filesystem squashfs \
    --backports true \
    --security true \
    --updates true \
    --source false \
    --apt-indices none \
    --apt-source-archives false \
    --archive-areas 'main contrib non-free' \
    --debootstrap-options "--include=apt-transport-https,gnupg,ca-certificates,openssl" \
    --apt-options "--allow-downgrades --allow-remove-essential --allow-change-held-packages --yes"

  lb build 2>&1 | tee "$WORKDIR/output/$IMAGE_NAME-$IMAGE_VERSION-build.log"
  if [ -f "$IMAGE_NAME-amd64.hybrid.iso" ]; then
    mv "$IMAGE_NAME-amd64.hybrid.iso" "$RUN_PATH/$IMAGE_NAME-$IMAGE_VERSION.iso" && \
      echo "Finished, created \"$RUN_PATH/$IMAGE_NAME-$IMAGE_VERSION.iso\""
    BUILD_ERROR_CODE=0
  else
    echo "Error creating ISO, see log file"
    BUILD_ERROR_CODE=2
  fi
  mv "$WORKDIR/output/$IMAGE_NAME-$IMAGE_VERSION-build.log" "$RUN_PATH/"

  popd >/dev/null 2>&1
  popd >/dev/null 2>&1

else
  echo "Unable to create temporary directory \"$WORKDIR\""
fi

popd  >/dev/null 2>&1

exit $BUILD_ERROR_CODE
