#!/usr/bin/bash
# Výměna jádra za to z akmods + instalace NVIDIA 580 LTS (proprietární) driveru.
# Postup kopíruje upstream projectbluefin/bluefin build_files/base/04-install-kernel-akmods.sh,
# jen s akmods-nvidia-lts místo akmods-nvidia-open.
set -euxo pipefail

: "${KERNEL:?KERNEL musí být předaný jako build-arg}"

### 1) Vyměnit jádro za to, ke kterému jsou postavené kmody --------------------
for pkg in kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra; do
    rpm --erase "$pkg" --nodeps || true
done

dnf5 -y install \
    /tmp/kernel-rpms/kernel-[0-9]*.rpm \
    /tmp/kernel-rpms/kernel-core-*.rpm \
    /tmp/kernel-rpms/kernel-modules-*.rpm

dnf5 -y install /tmp/kernel-rpms/kernel-devel-*.rpm || true

# Jádro se nesmí samo posunout — kmody jsou postavené přesně na tuhle verzi.
dnf5 versionlock add \
    kernel kernel-core kernel-modules kernel-modules-core kernel-modules-extra || true

### 2) Veřejný klíč, kterým Universal Blue podepisuje kmody -------------------
# Díky němu funguje Secure Boot bez vlastního MOK klíče (zapisuje se přes
# `ujust enroll-secure-boot-key`, heslo `universalblue`).
mkdir -p /etc/pki/akmods/certs
curl -fsSL -o /etc/pki/akmods/certs/akmods-ublue.der \
    https://github.com/ublue-os/akmods/raw/refs/heads/main/certs/public_key.der
grep -F -e "Universal Blue" /etc/pki/akmods/certs/akmods-ublue.der

### 3) NVIDIA 580 LTS ---------------------------------------------------------
rpm --import "https://download.copr.fedorainfracloud.org/results/ublue-os/staging/pubkey.gpg"

IMAGE_NAME="silverblue" AKMODNV_PATH="/tmp/akmods-rpms" MULTILIB=0 \
    /tmp/akmods-rpms/ublue-os/nvidia-install.sh

rm -f /usr/share/vulkan/icd.d/nouveau_icd.*.json
ln -sf libnvidia-ml.so.1 /usr/lib64/libnvidia-ml.so

### 4) POJISTKA: opravdu je to větev 580? -------------------------------------
# Kdyby ublue jednou přepnul nvidia-lts na novější větev, Pascal by tiše přestal
# fungovat. Radši ať build spadne tady, než aby stroj nenaběhl.
DRIVER_VERSION="$(modinfo -F version "/usr/lib/modules/${KERNEL}/extra/nvidia/nvidia.ko.xz")"
echo "### NVIDIA driver: ${DRIVER_VERSION} (jádro ${KERNEL})"
rpm -qa | grep -i nvidia | sort
case "${DRIVER_VERSION}" in
    580.*) echo "### OK — 580 LTS větev, Pascal (sm_61) je podporovaný" ;;
    *) echo "### CHYBA: očekávána větev 580, nalezeno ${DRIVER_VERSION} — Pascal by nenaběhl"; exit 1 ;;
esac

### 5) Kernel argumenty -------------------------------------------------------
mkdir -p /usr/lib/bootc/kargs.d
cat > /usr/lib/bootc/kargs.d/00-nvidia.toml <<'EOF'
kargs = ["rd.driver.blacklist=nouveau", "modprobe.blacklist=nouveau", "nvidia-drm.modeset=1", "initcall_blacklist=simpledrm_platform_driver_init"]
EOF

### 6) NVIDIA Container Toolkit — CDI průchod GPU do kontejnerů ---------------
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/rpm/nvidia-container-toolkit.repo \
    -o /etc/yum.repos.d/nvidia-container-toolkit.repo
dnf5 -y install nvidia-container-toolkit-base
nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place
rm -f /etc/yum.repos.d/nvidia-container-toolkit.repo

### 7) initramfs pro nové jádro ----------------------------------------------
export DRACUT_NO_XATTR=1
/usr/bin/dracut --no-hostonly --kver "${KERNEL}" --reproducible --tmpdir /boot -v \
    --add "ostree dmsquash-live dmsquash-live-autooverlay" \
    -f "/lib/modules/${KERNEL}/initramfs.img"
chmod 0600 "/lib/modules/${KERNEL}/initramfs.img"

### 8) Úklid ------------------------------------------------------------------
dnf5 clean all
rm -rf /var/cache/dnf /var/cache/libdnf5 /var/log/dnf* /tmp/rpms
