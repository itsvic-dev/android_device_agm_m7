# LineageOS 24.0 for the AGM M7: design

Status: sketch. Nothing here has been built. Paths are relative to the
LineageOS tree (`~/android` on pl-waw01, branch `lineage-24.0`, AOSP tag
`android-17.0.0_r1`).

Labels:

- **[verified]**: I read it in the source tree.
- **[inferred]**: my conclusion or a guess. Check it before you depend on it.

## 1. How the mainline and virtio trees work

### 1.1 Layers

```
device/virt/virtio_arm64only/lineage_virtio_arm64only_go.mk   (product)
  -> device/virt/virtio_arm64only/device.mk
     -> device/virt/virtio_arm64/device.mk
        -> device/virt/virtio-common/device-common.mk
           -> device/virt/virt-common/virt-common.mk
              -> device/mainline/common/mainline_common.mk

device/virt/virtio_arm64only/virtio_arm64only_go/BoardConfig.mk   (board)
  -> device/virt/virtio_arm64only/BoardConfig.mk   (clears TARGET_2ND_*)
     -> device/virt/virtio_arm64/BoardConfig.mk
        -> device/virt/virtio-common/BoardConfigCommon.mk
           -> device/virt/virt-common/BoardConfigVirtCommon.mk
              -> device/mainline/common/BoardConfigMainlineCommon.mk
```

[verified] All of these files.

- `device/mainline/common` is the generic layer for any device with a
  mainline or ACK kernel. Its `README.md` describes the integration: include
  `BoardConfigMainlineCommon.mk` in the board config and inherit
  `mainline_common.mk` in the product.
- `device/mainline/common/optional/` has one directory per component. Each has
  a `product.mk` and/or `board.mk` that is active only when a `TARGET_*`
  variable selects it. `optional/options.mk` sets the defaults with `?=`.
  `optional/README.md` lists all options. So a device selects HALs with
  variables. It does not list packages.
- `virt-common` adds VM parts: GRUB, A/B, virtual A/B, `vendor_boot`, VirtWifi,
  a GRUB boot control HAL, disk image tasks.
- `virtio-common` adds VirtIO parts: `virtgpu_detect`, `fstab.virtio`, virgl.

For the M7 only `device/mainline/common` is useful. The virt layers are tied to
GRUB, A/B and `vendor_boot`, which this phone cannot use.

### 1.2 Kernel

- [verified] `virtio-common/device-common.mk`: a source kernel at
  `kernel/virt/virtio` if it exists, else a prebuilt from
  `device/virt/kernel-virtio/<ver>/<arch>/<pagesize>/kernel`, copied with
  `PRODUCT_COPY_FILES += ...:kernel`.
- [verified] `BoardConfigVirtCommon.mk`: inline build uses
  `TARGET_KERNEL_CONFIG := gki_defconfig` plus fragments
  (`TARGET_KERNEL_CONFIG_EXT`), for example
  `kernel/mainline/configs/fragments/y/fbcon.config`.
- [verified] `mainline/common/optional/prebuilt_kernel/board.mk`: with
  `TARGET_PREBUILT_KERNEL`, all `*.ko` in the same directory become
  `BOARD_VENDOR_KERNEL_MODULES`. With `TARGET_KERNEL_MIXED_MODE=true`
  (default) it also reads `system_dlkm.modules.load` from that directory.
- [verified] `vendor/lineage/build/tasks/kernel.mk`: if `TARGET_KERNEL_SOURCE`
  (default `kernel/agm/m7`, from `vendor/lineage/config/BoardConfigKernel.mk`)
  does not exist and `TARGET_PREBUILT_KERNEL` is set, it uses the prebuilt.
  It prints a "deprecated" warning. That is OK for us.
- [verified] `hardware/mainline/common/dlkm_loader_mainline`: a vendor service
  loads `modules.load` from `/vendor/lib/modules` (and odm, system). Its rc
  sets `firmware_config/force_sysfs_fallback=1`, so ueventd loads firmware.
- [verified] `kernel/mainline/configs/`: `defconfigs/arm64/gki_defconfig`,
  `fragments/common.config` (Android needs: binder, cgroups, MEMCG, DM, EROFS,
  F2FS, ZRAM, USB configfs, ...), `fragments/android-base-pre/` (fixes for
  pristine defconfigs), `fragments/n/go.config` (`FTRACE` and `SLUB_DEBUG`
  off), `init/use_memfd.rc` (`sys.use_memfd=true`, so no ashmem is needed).
  Its README says it is based on `kernel/configs/b/android-6.12`. The Android
  17 files `kernel/configs/c/android-6.18/android-base.config` and
  `d/android-6.18/...` are empty in this tree.

### 1.3 Boot images

- [verified] virt uses `BOARD_BOOT_HEADER_VERSION := 4`, `BOARD_BOOTCONFIG`
  for `androidboot.*`, `vendor_boot` (100 MiB), LZ4 ramdisk, and the recovery
  ramdisk inside `vendor_boot` on A/B.
- [verified] `build/make/core/board_config.mk`: `vendor_boot` is built only if
  the header version is 3 or more. With version 0 the build makes a classic
  `boot.img` and `recovery.img`.
- [verified] `build/make/core/Makefile`: without `vendor_boot` and without GKI,
  `--cmdline $(INTERNAL_KERNEL_CMDLINE)`, `--base $(BOARD_KERNEL_BASE)` and
  `--pagesize $(BOARD_KERNEL_PAGESIZE)` go into `boot.img`.
  `BOARD_MKBOOTIMG_ARGS` is appended to the mkbootimg call for boot and
  recovery. `BOARD_RAMDISK_USE_XZ` gives `xz --check=crc32 --lzma2=dict=32MiB`.
- [verified] `board_config.mk`: `BOARD_BOOTCONFIG` adds `bootconfig` to the
  cmdline. Header v0 has no bootconfig section, so we must not set it.
- [verified] `system/tools/mkbootimg/mkbootimg.py`: v0 header has a 512 byte
  `cmdline` and a 1024 byte `extra_cmdline`. Addresses are `base + offset`.
  Defaults: base `0x10000000`, kernel `0x8000`, ramdisk `0x01000000`, second
  `0x00f00000`, tags `0x100`.
- [inferred] `build/soong/fsgen/boot_imgs.go` can also make boot images in
  Soong-only builds. It does not seem to pass base and offsets. LineageOS
  builds images with Make (`m bacon`), so this should not matter. Check it if
  boot.img has wrong addresses.

### 1.4 Partitions, fstab, first stage mount

- [verified] virt: `PRODUCT_USE_DYNAMIC_PARTITIONS`, `super` 4 GiB (ext4) or
  3 GiB (erofs) on non-A/B, one group with system, system_ext, product, vendor,
  odm, system_dlkm, vendor_dlkm. `BOARD_USES_METADATA_PARTITION := true`.
- [verified] virtio fstab is generated by a Soong `genrule`
  (`virtio-common/configs/fstab/Android.bp`) that concatenates
  `virt-common/configs/fstab/fstab.virt-*` with `fstab.virtio-common`. It is
  installed to vendor and `vendor_ramdisk` (`vendor_ramdisk_available`).
- [verified] `system/fs/fs_mgr/libfstab/fstab.cpp`: the default fstab is the
  first that exists of `fstab.<suffix>` for `fstab_suffix`, `hardware`,
  `hardware.platform`, searched in `/odm/etc`, `/vendor/etc`, `/system/etc`,
  `/first_stage_ramdisk/...`, and `/fstab.` in the ramdisk root.
- [verified] `system/core/init/devices.cpp`: `/dev/block/by-name/<name>` is
  made only for partitions on a boot device. `androidboot.boot_devices=any`
  makes it for all devices. `TARGET_INITIAL_BRINGUP` sets `boot_devices=any`
  in `MAINLINE_COMMON_ANDROIDBOOT_PARAMS`. **We must not use that**: the eMMC
  also has `userdata` and others, and the names would collide.
- [verified] `system/fs/fs_mgr/libfstab/fstab.cpp` `GetBootDevices()`: order is
  DT `/firmware/android/boot_devices`, then bootconfig, then cmdline.
- [verified] `system/core/init/property_service.cpp`: `ro.boot.*` comes from DT
  (`/proc/device-tree/firmware/android/*`) first, then bootconfig, then
  cmdline. A read-only property keeps its first value. So DT values win over
  anything LK writes on the cmdline.
- [verified] `system/core/init/first_stage_init.cpp`, `util.cpp`: recovery mode
  is `access("/system/bin/recovery") == 0` in the ramdisk, unless
  `androidboot.force_normal_boot=1`.
- [verified] `system/vold/MetadataCrypt.cpp`, `libfstab`: `keydirectory=` turns
  on metadata encryption, which uses dm-default-key. dm-default-key is an ACK
  patch (`kernel/mainline/configs/fragments/android-base-pre/arm64.config`
  lists `CONFIG_DM_DEFAULT_KEY` as missing).

### 1.5 Graphics

- [verified] `optional/options.mk`: `TARGET_GRAPHICS ?= mesa`. With
  `swiftshader`: EGL is ANGLE (`ro.hardware.egl=angle`), Vulkan is SwiftShader
  (`org.lineageos.device.graphics.vulkan.swiftshader`), allocator is
  `minigbm-upstream`. Composer is `drm_hwcomposer` (upstream variant, HWC3,
  in an APEX), or `drmfb-composer` when `TARGET_INITIAL_BRINGUP=true`.
- [verified] virt uses Mesa for virgl and llvmpipe, plus SwiftShader
  ("pastel"), and picks one at boot from `ro.boot.graphics`
  (`virt-common/configs/init/init.virt.rc`).
- [verified] `external/minigbm-upstream/drv.c`: unknown DRM drivers fall back
  to `dumb_generic`. `vendor.minigbm.generic_backend=dumb_generic` forces it.
- [verified] `hardware/mainline/common/interfaces/graphics/composer/drmfb/README.md`:
  drmfb-composer does client composition only, and converts any 32-bit RGB
  client target to a linear XRGB8888 dumb buffer if the plane cannot scan out
  the client format. It forwards damage through `FB_DAMAGE_CLIPS`.

### 1.6 Go and low RAM

- [verified] `mainline_common.mk`: with `PRODUCT_IS_GO=true` it inherits
  `go_defaults$(PRODUCT_GO_DEFAULTS_SUFFIX).mk`, sets DM preopt with `verify`,
  adds `overlays/overlay-go`, `go_handheld_core_hardware.xml`.
  `BoardConfigMainlineCommon.mk` sets `MALLOC_SVELTE` and adds
  `properties/product_go.prop` and `vendor_go.prop`
  (`ro.config.per_app_memcg=false`).
- [verified] `build/make/target/product/go_defaults_common.mk`:
  `ro.config.low_ram=true`, `MALLOC_LOW_MEMORY` (non-eng), lmkd props.
- [verified] `lineage_virtio_arm64only_go.mk`: `core_64_bit_only.mk`,
  `generic_no_telephony.mk`, `languages_full.mk`,
  `vendor/lineage/config/common_mini_go_phone.mk`, `PRODUCT_IS_GO := true`.
  `virt-common.mk` adds `phone-xhdpi-1024-dalvik-heap.mk` for Go.
- [verified] `common_mini_go_phone.mk` inherits `common_mini_phone.mk`, which
  inherits `telephony.mk`.
- [verified] `virt-common/configs/init/init.low_performance.rc` shows the extra
  low RAM props virt applies at runtime.

## 2. Plan for the M7

### 2.1 Product and board

- Product `lineage_m7` (`lineage_m7.mk`): `core_64_bit_only.mk`,
  `generic_no_telephony.mk`, `languages_full.mk`, then the content of
  `common_mini_go_phone.mk` without telephony (`PRODUCT_TYPE := go`,
  `common_mobile_mini.mk`, `wifionly.mk`), `PRODUCT_IS_GO := true`.
  [inferred] This combination is not used by any tree here. Check that
  `common_mobile_mini.mk` does not need something from `common_mini_phone.mk`.
- `device.mk` inherits only `device/mainline/common/mainline_common.mk`.
- `BoardConfig.mk` includes only `BoardConfigMainlineCommon.mk`. Arch block as
  in `virtio_arm64` with the `TARGET_2ND_*` values cleared, like
  `virtio_arm64only/BoardConfig.mk`.
- Do not set `TARGET_INITIAL_BRINGUP`. It forces `boot_devices=any`,
  fbkeyboard, the cuttlefish health HAL and drmfb-composer. Set the options one
  by one in `device.mk`.

### 2.2 Kernel

- Prebuilt: `TARGET_PREBUILT_KERNEL := device/agm/m7-kernel/Image.gz-dtb`.
  `Image.gz-dtb` is `cat Image.gz mt6739-agm-m7.dtb`, the same layout that
  `scripts/mkboot.py` builds. Put the `*.ko` files (at least
  `mt6739-wlan.ko`, `cfg80211.ko`, `powervr.ko`) in the same directory.
  `TARGET_KERNEL_MIXED_MODE := false`, so no `system_dlkm.modules.load` is
  needed.
- [inferred] Best source: a new flake output in `nixos-agm-m7`
  (`packages.aarch64-linux.android-kernel`) built from `linux-mt6739`
  `linux-7.2` with `agm-m7.config` + `android.config`. Then copy the output to
  `device/agm/m7-kernel/` on pl-waw01. Keep `device/agm/m7-kernel/` out of git
  or in its own repo.
- The DTB must still be built with `-@` and keep `lk-odm-overlay-sink`.
- Add to the DTB (shared with NixOS, it does no harm there):

  ```
  firmware {
      android {
          compatible = "android,firmware";
          hardware = "m7";
          boot_devices = "soc/11240000.mmc";
      };
  };
  ```

  DT wins over the cmdline for both values ([verified], 1.4). Then the cmdline
  can drop them and LK cannot override them.
- `configs/kernel/android.config` is the fragment on top of `agm-m7.config`.
  Main points:
  - Binder: C binder (`ANDROID_BINDER_IPC`, `ANDROID_BINDERFS`). Do not use
    `binder.impl=rust` from `MAINLINE_COMMON_KERNEL_PARAMS` unless Rust binder
    is built.
  - No ashmem: `use_memfd.rc` from `kernel/mainline/configs/init`.
  - SELinux, audit, seccomp filter, PSI, cgroups (freezer, cpuset, cpuacct,
    sched, uclamp), BPF JIT and BPF classifiers, the netfilter list from
    `android-base.config`, EROFS, F2FS security xattrs, fscrypt, quota, FUSE,
    uinput, uhid, DMA-BUF system heap, sync_file, configfs FunctionFS,
    `PM_WAKELOCKS`.
  - Remove `USB_CDC_COMPOSITE` (g_cdc). A legacy gadget holds the UDC and
    configfs cannot bind adb.
  - Keep MEMCG on. Keep `slub_debug=-` on the cmdline.
  - [inferred] `n/go.config` (no FTRACE) can save RAM, but perfetto, atrace
    and some BPF programs want tracepoints. Start with FTRACE on.
  - [inferred] With `BOARD_RAMDISK_USE_XZ`, the kernel needs `RD_XZ`.

### 2.3 boot.img v0

Values, from `scripts/mkboot.py` in `nixos-agm-m7`:

| Field | Value | Build variable |
|---|---|---|
| header version | 0 | `BOARD_BOOT_HEADER_VERSION := 0`, `--header_version 0` |
| page size | 2048 | `BOARD_KERNEL_PAGESIZE := 2048` |
| base | 0x40000000 | `BOARD_KERNEL_BASE := 0x40000000` |
| kernel | 0x40200000 | `--kernel_offset 0x00200000` |
| ramdisk | 0x45000000 | `--ramdisk_offset 0x05000000` |
| second | 0x40f00000 | `--second_offset 0x00f00000` |
| tags | 0x44000000 | `--tags_offset 0x04000000` |

- No `vendor_boot`, no `init_boot`, no dtbo, no AVB (`BOARD_AVB_ENABLE := false`).
- `BOARD_BOOTIMAGE_PARTITION_SIZE` and `BOARD_RECOVERYIMAGE_PARTITION_SIZE`
  are 25165824. The build checks the image size against them.
- The cmdline in `BoardConfig.mk` is 396 bytes. `bootopt=64S3,32N2,64N2` is
  first, like in `mkboot.py`. [inferred] LK reads only the 512 byte `cmdline`
  field; keep the total under 511 bytes. Moving `androidboot.hardware` and
  `androidboot.boot_devices` to the DT saves about 65 bytes.
- [inferred] mkbootimg writes `os_version` and `os_patch_level` into the v0
  header. Stock 8.1 images have them too, so LK should accept them.
- Check after the first build:
  `unpack_bootimg --boot_img boot.img` must show the addresses above.

### 2.4 Ramdisk size (16 MiB limit)

- The normal `boot.img` ramdisk holds only first stage init, `fstab.mt6739`, and
  some small tools. [inferred] It should be 2 to 4 MiB compressed.
- The LineageOS Recovery ramdisk is the risk. [inferred] It can pass 16 MiB
  with LZ4. Use `BOARD_RAMDISK_USE_XZ := true` (same compression as the NixOS
  initrd that boots now). Remove recovery features we do not need if it is
  still too big.
- Build check: `build/tasks/ramdisk-size-check.mk`. It makes `boot.img` and
  `recovery.img` depend on a stamp that fails when `ramdisk.img` or
  `ramdisk-recovery.img` is bigger than `AGM_M7_MAX_RAMDISK_SIZE` (16777216).
  [verified] Device task files are included at the end of
  `build/make/core/Makefile` (`device/*/*/build/tasks/*.mk`), after
  `INSTALLED_RAMDISK_TARGET`, `recovery_ramdisk` and the image targets exist.
  [inferred] The extra prerequisite on the image targets works because the
  recipe stays in the core Makefile.
- Also keep `scripts/mkboot.py`'s check in mind: it checks the same limit.

### 2.5 Which partition boots Android

- Android `boot.img` is flashed to the eMMC `recovery` partition. LK boots it
  after `reboot recovery`. NixOS stays on `boot`.
- [verified] A normal `boot.img` ramdisk has no `/system/bin/recovery`, so
  init boots Android even when LK loads it from `recovery`.
- LineageOS Recovery (`recovery.img`) has no partition of its own. Flash it to
  `recovery` only when you need it, then flash `boot.img` back.
  `BOARD_USES_FULL_RECOVERY_IMAGE := true`. Do not use
  `install-recovery.sh` or any OTA recovery update: it would write
  `recovery.img` over Android.
- [inferred] A plain `reboot` from Android goes to NixOS, and
  `reboot recovery` goes back to Android.
- The fstab has no `/boot`, `/recovery` or `/misc` entries, so Android cannot
  write those eMMC partitions through fs_mgr.

### 2.6 microSD layout and fstab

GPT on mmcblk1 (MSDC1, `11240000.mmc`):

| Name | Size | Content |
|---|---|---|
| `metadata` | 16 MiB | ext4, made by fs_mgr (`formattable`) |
| `super` | 4 GiB | `super.img` from the build (system, system_ext, product, vendor, odm, erofs) |
| `userdata` | about 17 GiB | f2fs, made by fs_mgr on first boot |

- `BOARD_SUPER_PARTITION_SIZE := 4294967296`, one group
  `agm_dynamic_partitions` of super minus 4 MiB, erofs with `lz4hc`.
  [inferred] lz4hc trades CPU for less I/O on the SD card. Measure against
  uncompressed erofs.
- No dlkm partitions: modules go to `/vendor/lib/modules`.
- Flash `super.img` from NixOS or from the Mac card reader with `dd`
  (`simg2img` first if the image is sparse).
- `fstab.mt6739` goes to the ramdisk root (`$(TARGET_COPY_OUT_RAMDISK)/fstab.mt6739`)
  and to `/vendor/etc/fstab.mt6739`. First stage mounts the logical partitions and
  `/metadata`. `/data` is `latemount`.
- The hardware name is `mt6739`, not `m7`. LK writes
  `/firmware/android/hardware = "mt6739"` into the DT, and init and libfstab
  read the DT before the cmdline. So `androidboot.hardware=m7` has no effect,
  and the fstab and init files must use the `mt6739` suffix.
- The SD card `metadata` partition is labelled `sd_metadata`. The eMMC has a
  stock `metadata` partition (`mmcblk0p8`) that probes first. First stage init
  matches required devices by partition name, takes the eMMC one, and makes no
  `by-name` link because the eMMC is not a boot device. It then waits 20 s.
- `androidboot.boot_devices=soc/11240000.mmc`. [inferred] The name is the
  sysfs path after `/devices/platform/`. Our DTS has the MMC nodes under
  `soc`, so it is `soc/11240000.mmc`, not `11240000.mmc`. Check with
  `readlink -f /sys/block/mmcblk1` on NixOS.
- Encryption: FBE (`fileencryption=aes-256-xts:aes-256-cts:v2`) without
  `keydirectory`, so no metadata encryption (no dm-default-key on mainline).
  [inferred] `agm-m7.config` has `CRYPTO_AES_ARM64_CE_BLK`, so the A53 likely
  has AES instructions. If not, use `fileencryption=adiantum`.
- eMMC access: only `nvdata` (Wi-Fi NVRAM and MAC), mounted `ro,noload`, no
  `check`, no `formattable`, at `/mnt/vendor/nvdata`. Firmware
  (`WMT_SOC.cfg`, `ROMv2_lm_patch_*`, `WIFI_RAM_CODE_6755`, `rgx.fw.signed`)
  is copied into our own `/vendor/firmware` at build time from
  `vendor/agm/m7` (extract once from the stock `vendor` image). This avoids
  mounting the stock `vendor` partition. The NVRAM file name the driver wants
  is `mt6739-wlan-nvram.bin`; add a symlink in `/vendor/firmware` to
  `/mnt/vendor/nvdata/APCFG/APRDEB/WIFI` (like `nixos/vendor.nix`).

### 2.7 Graphics for milestone 1

- `TARGET_GRAPHICS := swiftshader`: ANGLE (GLES on Vulkan) on SwiftShader
  (CPU Vulkan). This is the software path that mainline/common supports today.
- Allocator: `minigbm-upstream`, platform `generic`, with
  `vendor.minigbm.generic_backend=dumb_generic` so buffers are DRM dumb
  buffers on `mt6739-dbi`.
- Composer: `drm_hwcomposer` as requested. **Risk** [inferred]: SurfaceFlinger
  uses RGBA8888 (DRM `ABGR8888`) client targets, and `mt6739-dbi` exposes
  only XRGB8888. drm_hwcomposer then cannot put the client target on the plane.
  Two fixes:
  1. Add `ABGR8888`/`XBGR8888` (and maybe `RGB565`) to the `mt6739-dbi`
     plane. OVL has byte swap and alpha control.
  2. Use `drmfb-composer` (`TARGET_GRAPHICS_COMPOSER_HAL := drmfb-composer`).
     It converts to XRGB8888 and sends damage clips, which also fits a
     command-mode panel. I recommend this one for the first boot, and
     drm_hwcomposer after fix 1.
- [inferred] mt6739-dbi has no vblank IRQ. The DRM core then sends fake vblank
  events, but HWC vsync timing is synthetic. virtio sets
  `ro.vendor.hwc.drm.present_fence_not_reliable=true` and
  `debug.sf.vsync_reactor_ignore_present_fences=true`; we copy them.
- Recovery: `TARGET_RECOVERY_PIXEL_FORMAT := BGRX_8888` maps to
  `DRM_FORMAT_XRGB8888` in `bootable/recovery/minui/graphics_drm.cpp`
  [verified]. The default would be RGB565.
- Later: Mesa `imagination` Vulkan (PowerVR) with ANGLE on top, or Zink. The
  `mesa` option in mainline/common already exists; it needs the patched
  firmware interface and `powervr.ko`.

### 2.8 Go and low RAM

- `PRODUCT_IS_GO := true` (1 GiB defaults, not `_512`).
  `phone-xhdpi-1024-dalvik-heap.mk`.
- `ro.sf.lcd_density=120`. At 240x320 this is 320x427 dp, which meets the
  320 dp minimum.
- ZRAM: `zramsize=50%`, zstd (already in the kernel), `swapon_all` on boot.
- `TARGET_SUPPORTS_SUSPEND := false` for now (no SPM firmware; suspend is not
  tested on mainline).
- [inferred] Remove more if RAM is too tight: `languages_full.mk`,
  `PRODUCT_SIZE := mini` apps, print and Bluetooth stacks.

### 2.9 What we drop

- Telephony: `generic_no_telephony.mk`, no `telephony.mk`, `wifionly.mk`.
- Bluetooth (`TARGET_BLUETOOTH_HAL := none`), camera, sensors
  (`TARGET_SENSORS_HAL := none`), vibrator (TODO: check the hardware), NFC.
- GRUB, A/B, virtual A/B, `vendor_boot`, VirtWifi, virtio parts.
- `MAINLINE_COMMON_ANDROIDBOOT_PARAMS` (it would set
  `init_fatal_reboot_target=recovery`, which is Android itself here, so a
  crash loop) and parts of `MAINLINE_COMMON_KERNEL_PARAMS` (`binder.impl=rust`,
  `rw`, `log_buf_len=4M`).

### 2.10 Input

- `mt6779-keypad.kl`: soft keys MENU and BACK, D-pad, digits, STAR, POUND.
  Call key mapped to HOME as a proposal (there is no HOME key). Side key F11
  (TODO).
- `mtk-pmic-keys.kl`: red key (KEY_POWER) is POWER.
- `mt6779-keypad.kcm`: `type NUMERIC`. [inferred] TextKeyListener then uses
  multi-tap for text fields.
- Touch `.idc` file: TODO, the input name comes from the edt-ft5x06 driver
  (`EP0...M09` style), read it from `/proc/bus/input/devices`.
- Nav bar stays on (`qemu.hw.mainkeys=0`) until the key mapping is final.

## 3. Milestone 1 steps

1. Kernel: build with `android.config`, add `/firmware/android` to the DTB,
   remove g_cdc. Boot NixOS with it once, to check nothing breaks.
2. Write the GPT on the SD card (`metadata`, `super`, `userdata`). Back up the
   card first.
3. `breakfast m7`, `m bootimage superimage` (not now: pl-waw01 is busy).
4. `unpack_bootimg` check, ramdisk size check.
5. `dd` `super.img` to the SD `super` partition.
6. `fastboot flash recovery boot.img`, `reboot recovery` from NixOS.
7. Expect adb over USB, then the launcher on SwiftShader.

## 4. Open questions and risks

1. **LK cmdline.** What does LK add (for example `androidboot.hardware=`,
   `androidboot.mode=`, `androidboot.serialno=`,
   `androidboot.verifiedbootstate=`)? Is it different when it boots
   `recovery`? Get `/proc/cmdline` from NixOS after `reboot recovery`.
   The DT `/firmware/android` node is the safe way for our values.
2. **extra_cmdline.** Does LK read the 1024 byte `extra_cmdline` field? I
   assume not. Keep the cmdline under 511 bytes.
3. **boot_devices name**: `soc/11240000.mmc` or `11240000.mmc`.
4. **UDC name** for `sys.usb.controller` (`ls /sys/class/udc`). I wrote
   `musb-hdrc.0.auto` as a guess.
5. **MUSB PIO only**: adb works, but it is slow. FunctionFS on MUSB is not
   tested here.
6. **Kernel version 7.2 vs. VINTF.** Android 17 matrices know up to
   android-6.18. `PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false` is
   copied from virt. [inferred] Runtime checks (bpfloader, netd, libvintf)
   may still complain. Check `logcat` for VINTF and BPF errors first.
7. **BPF and netd.** Missing netfilter or BPF options make bpfloader or netd
   fail and can cause a reboot loop. Validate with
   `kernel/mainline/configs/utilities/validate_kernel_config.py`.
8. **drm_hwcomposer on mt6739-dbi**: formats, PRIME import of minigbm dumb
   buffers, no vblank. See 2.7.
9. **RAM.** 913 MiB with the modem. SwiftShader and ANGLE use CPU and RAM.
   Measure with `dumpsys meminfo` and `/proc/pressure/memory`. Keep the modem
   off for Android at first (no RIL anyway).
10. **Recovery ramdisk size** with xz. Unknown until the first build.
11. **Rescue Party and `init_fatal_reboot_target`.** Both reboot to recovery,
    which is Android again. Without `/misc` the bootloader message cannot be
    written. [inferred] A boot loop needs a manual `reboot` (to NixOS) or a
    battery pull. Consider `androidboot.init_fatal_reboot_target=bootloader`
    (fastboot mode, the init default).
12. **Plain reboot goes to NixOS.** Should Android reboots stay in Android? It
    needs a kernel change (default reboot mode for the `mtk_wdt` restart
    handler) or a reboot hook. Decide later.
13. **Wi-Fi HAL.** Which Wi-Fi HAL and legacy HAL work with the staging gen2
    driver over nl80211. `android.hardware.wifi-service` is a placeholder.
    Module load order: dlkm_loader_mainline runs in `on init`, before the
    nvdata mount; so `BOARD_VENDOR_KERNEL_MODULES_LOAD := false` keeps
    `modules.load` empty ([verified] `build/make/core/Makefile`: empty means
    all modules, `false` means none) and `init.mt6739.rc` loads `mt6739-wlan` in
    `post-fs-data`. Check the SELinux rules for this.
14. **SELinux.** Permissive at first (`androidboot.selinux=permissive`,
    userdebug only). The skeleton `sepolicy/vendor` labels the SD partitions
    and nvdata only.
15. **Ashmem.** [inferred] `use_memfd.rc` is enough on Android 17. Check
    `libcutils` if apps fail with ashmem errors.
16. **FBE without metadata encryption.** [inferred] Android 17 should accept
    it on a userdebug build. If vold refuses, test without encryption first.
17. **Audio.** Mainline audio HAL with `TARGET_AUDIO_MAINLINE_UCM_PROFILES :=
    none`; ship our UCM profile (`nixos/ucm2`) as a `prebuilt_etc` under
    `/vendor/etc/alsa/ucm2`. Not needed for milestone 1. Keep the line out
    volume low, the speaker is loud.
18. **Health HAL.** `default-aidl` reads `/sys/class/power_supply`. Check the
    property names of `mt6357-charger` and `hl7005`.
19. **Soong-only images.** If this branch makes boot images in Soong, base
    and offsets may be lost (1.3).
