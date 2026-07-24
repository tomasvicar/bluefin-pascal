# Bluefin + NVIDIA 580 LTS (proprietarni) driver = jediná větev, která umí Pascal.
#
# Proč to takhle: upstream `-open` kmody začínají u Turingu, takže GTX 1070 / GT 1030
# na oficiálních nvidia image nenaběhnou. Universal Blue ale staví `akmods-nvidia-lts`
# z negativo17 repa `fedora-nvidia-580` s KERNEL_MODULE_TYPE=kernel — tedy přesně
# proprietární 580 modul. Ten sem jen zkopírujeme, nic se nekompiluje.
#
# ⚠️ KERNEL musí PŘESNĚ sedět na verzi, pro kterou jsou kmody postavené. Base image má
#    zpravidla jiné jádro, proto se tady jádro vymění za to z akmods — stejně jako to
#    dělá sám Bluefin v build_files/base/04-install-kernel-akmods.sh.
#    Správnou hodnotu KERNEL zjišťuje CI automaticky, natvrdo ji needituj.

ARG BASE_IMAGE="ghcr.io/ublue-os/bluefin-dx"
ARG BASE_TAG="stable"
ARG AKMODS_FLAVOR="main"
ARG FEDORA_VERSION="44"
ARG KERNEL="7.1.4-202.fc44.x86_64"

# Podepsané, předpřipravené RPM od Universal Blue — obojí musí být na stejné jádro.
FROM ghcr.io/ublue-os/akmods:${AKMODS_FLAVOR}-${FEDORA_VERSION}-${KERNEL} AS akmods
FROM ghcr.io/ublue-os/akmods-nvidia-lts:${AKMODS_FLAVOR}-${FEDORA_VERSION}-${KERNEL} AS akmods-nvidia

FROM ${BASE_IMAGE}:${BASE_TAG}

ARG KERNEL
ARG FEDORA_VERSION

COPY --from=akmods        /kernel-rpms /tmp/kernel-rpms
COPY --from=akmods        /rpms        /tmp/akmods
COPY --from=akmods-nvidia /rpms        /tmp/akmods-rpms

COPY build_files/ /tmp/build_files/

# přes `bash`, ne přímo — Git na Windows nemusí přenést execute bit
RUN bash /tmp/build_files/10-kernel-nvidia-lts.sh \
 && rm -rf /tmp/build_files /tmp/kernel-rpms /tmp/akmods /tmp/akmods-rpms

# ---------------------------------------------------------------------------
# TVOJE VLASTNÍ ZÁSAHY — až AŽ bude ověřeno, že rebase i rollback fungují.
# Přidávej po jedné věci. Experimenty patří do distroboxu, ne sem.
# ---------------------------------------------------------------------------
# COPY files/ /

RUN bootc container lint
