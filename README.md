# bluefin-pascal

Vlastní [bootc](https://bootc-dev.github.io/bootc/) image: **Bluefin + proprietární NVIDIA 580 LTS driver**,
tedy jediná větev, která ještě umí **Pascal** (GTX 1070, GT 1030 — `sm_61`).

Upstream tuhle kombinaci nenabízí: oficiální `-open` kernel moduly začínají až u Turingu.
Universal Blue ale staví podepsané kmody `akmods-nvidia-lts` z negativo17 repa
`fedora-nvidia-580` (`KERNEL_MODULE_TYPE=kernel`) — tady se jen **zkopírují**, nic se nekompiluje.

## Jak to funguje

```
ghcr.io/ublue-os/bluefin-dx:stable          ← base (GNOME, ujust, brew, distrobox, dx)
  + ghcr.io/ublue-os/akmods:main-44-<K>     ← jádro <K> (base má jiné, vymění se)
  + ghcr.io/ublue-os/akmods-nvidia-lts:…    ← podepsaný NVIDIA 580 kmod na jádro <K>
  = ghcr.io/tomasvicar/bluefin-pascal:latest
```

Kmod je postavený na **přesnou** verzi jádra, takže se jádro base image nahradí tím z akmods —
stejný postup jako upstream `projectbluefin/bluefin` v `build_files/base/04-install-kernel-akmods.sh`.
Verzi jádra zjišťuje CI sama (`.github/workflows/build.yml`, krok *Zjistit jádro…*), needituj ji ručně.

**Pojistka:** build ověří, že nainstalovaný driver je opravdu větev `580.*`, a jinak **selže**.
Kdyby ublue jednou `nvidia-lts` přepnul na novější větev, dozvíš se to z rozbitého buildu,
ne z nebootujícího stroje.

## Secure Boot

Kmody jsou podepsané klíčem Universal Blue → **vlastní MOK klíč nepotřebuješ**. Na stroji stačí:

```bash
ujust enroll-secure-boot-key     # heslo: universalblue
```

## Nasazení na stroj

Image je **veřejný** — přihlašování k `ghcr.io` není potřeba, jde to i z čerstvě
nainstalovaného systému:

```bash
sudo bootc switch ghcr.io/tomasvicar/bluefin-pascal:latest
systemctl reboot
```

Po rebootu:

```bash
nvidia-smi                                            # musí hlásit driver 580.x
sudo bootc status                                     # běžíš na svém image
podman run --rm --device nvidia.com/gpu=all \
  nvcr.io/nvidia/cuda:12.6.0-base-ubi9 nvidia-smi     # GPU projde do kontejneru
```

Když se něco pokazí: reboot → v boot menu předchozí deployment, nebo `sudo bootc rollback`.
Zpátky na čistý upstream: `sudo bootc switch ghcr.io/ublue-os/bluefin-dx:stable`.

### Podepisování image (volitelné, doděláš později)

```bash
cosign generate-key-pair          # BEZ hesla
gh secret set SIGNING_SECRET < cosign.key
git add cosign.pub && rm cosign.key
```
Dokud secret není nastavený, podpisový krok se přeskočí a `bootc switch` se používá
**bez** `--enforce-container-sigpolicy`.

## Co sem přidávat (a co ne)

| Vrstva | Kam | |
|---|---|---|
| NVIDIA driver, udev pravidla, kernel argumenty | **image** | systémové a stabilní |
| CLI nástroje | Homebrew | mění se často |
| GUI appky | Flatpak | sandbox |
| Vendor SW, `apt` svět, experimenty | distrobox | **sem patří všechno rozdělané** |
| Dev prostředí projektu | devcontainer + `uv` | zdroj pravdy je repo projektu |

Zapékej **málo a stabilní**. Vlastní soubory přidávej do `files/` a odkomentuj `COPY files/ /`
v `Containerfile` — ale až potom, co ověříš, že rebase i rollback fungují. Po jedné věci.

## Meze, které tenhle image neposune

- **CUDA 12.x je strop.** CUDA 13 Pascal vyhodila, PyTorch wheels od 2.8 taky (`sm_61` není v buildech).
  Řeš to tagem base image v devcontaineru, ne na hostu.
- **580 je zamrzlá větev** — security-only do 10/2028, zatímco Fedora jádro pod ní jde dál.
  Až build spadne natrvalo, je to signál na výměnu karty, ne na hackování jádra.
- **Vendor kernel moduly** (kamera mikroskopu apod.) ublue nestaví. Ty by se musely kompilovat
  a podepisovat vlastním klíčem při každém posunu jádra — to je nejdražší část celé cesty.

Kontext a rozhodování: `14-vlastni-image-nvidia-legacy.md` a `13-instalace-bluefin.md` v poznámkách.
