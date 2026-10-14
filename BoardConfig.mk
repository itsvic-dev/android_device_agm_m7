#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/agm/m7

# Must be set before mainline/common, its prebuilt_kernel/board.mk reads them.
# Image.gz with mt6739-agm-m7.dtb appended, plus *.ko next to it (see DESIGN.md)
TARGET_PREBUILT_KERNEL := device/agm/m7-kernel/Image.gz-dtb
TARGET_KERNEL_MIXED_MODE := false

include device/mainline/common/BoardConfigMainlineCommon.mk

BOARD_MESA3D_VULKAN_DRIVERS := imagination

# Arch
TARGET_ARCH := arm64
TARGET_ARCH_VARIANT := armv8-a
TARGET_CPU_ABI := arm64-v8a
TARGET_CPU_ABI2 :=
TARGET_CPU_VARIANT := cortex-a53

TARGET_2ND_ARCH :=
TARGET_2ND_ARCH_VARIANT :=
TARGET_2ND_CPU_ABI :=
TARGET_2ND_CPU_ABI2 :=
TARGET_2ND_CPU_VARIANT :=

# Boot image (MediaTek LK accepts header version 0 only)
BOARD_BOOT_HEADER_VERSION := 0
BOARD_KERNEL_BASE := 0x40000000
BOARD_KERNEL_PAGESIZE := 2048
BOARD_MKBOOTIMG_ARGS += \
    --header_version $(BOARD_BOOT_HEADER_VERSION) \
    --kernel_offset 0x00200000 \
    --ramdisk_offset 0x05000000 \
    --second_offset 0x00f00000 \
    --tags_offset 0x04000000

BOARD_RAMDISK_USE_XZ := true

# LK at 0x46000000 limits the ramdisk at 0x45000000 to 16 MiB, see build/tasks/ramdisk-size-check.mk
AGM_M7_MAX_RAMDISK_SIZE := 16777216

# Bootloader
TARGET_BOOTLOADER_BOARD_NAME := m7
TARGET_NO_BOOTLOADER := true

# Filesystem
TARGET_USERIMAGES_USE_EXT4 := true
TARGET_USERIMAGES_USE_F2FS := true
BOARD_USERDATAIMAGE_FILE_SYSTEM_TYPE := f2fs

# Kernel
TARGET_KERNEL_ARCH := arm64

# The header cmdline field is 512 bytes; LK ignores extra_cmdline (TODO: verify)
BOARD_KERNEL_CMDLINE := \
    bootopt=64S3,32N2,64N2 \
    earlycon=pstoreram,0x4445f000 \
    keep_bootcon \
    mtk_wdt_early=0x10007000,30 \
    clk_ignore_unused \
    regulator_ignore_unused \
    slub_debug=- \
    firmware_class.path=/vendor/firmware/ \
    printk.devkmsg=on \
    loop.max_part=7 \
    log_buf_len=1M \
    vt.global_cursor_default=0 \
    androidboot.boot_devices=soc/11240000.mmc \
    androidboot.selinux=permissive \
    androidboot.init_fatal_reboot_target=bootloader \
    androidboot.verifiedbootstate=orange

# "false" gives an empty modules.load; mt6739-wlan needs /mnt/vendor/nvdata, init.mt6739.rc loads it
BOARD_VENDOR_KERNEL_MODULES_LOAD := false

# TODO: list the modules that must load in recovery (none for milestone 1)
RECOVERY_KERNEL_MODULES :=

# Partitions (all on the microSD card)
BOARD_FLASH_BLOCK_SIZE := 4096
BOARD_BOOTIMAGE_PARTITION_SIZE := 25165824
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 25165824
BOARD_USES_METADATA_PARTITION := true

# AOSP 17 defaults to A/B. LK knows no slots and we boot from one recovery partition.
AB_OTA_UPDATER := false

BOARD_SUPER_PARTITION_SIZE := 4294967296
BOARD_SUPER_PARTITION_GROUPS := agm_dynamic_partitions
BOARD_AGM_DYNAMIC_PARTITIONS_PARTITION_LIST := system system_ext product vendor odm
BOARD_AGM_DYNAMIC_PARTITIONS_SIZE := 4290772992

BOARD_EROFS_COMPRESSOR := lz4hc,9
$(foreach p, SYSTEM SYSTEM_EXT PRODUCT VENDOR ODM, \
    $(eval BOARD_$(p)IMAGE_FILE_SYSTEM_TYPE := erofs))

TARGET_COPY_OUT_SYSTEM_EXT := system_ext
TARGET_COPY_OUT_PRODUCT := product
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_ODM := odm

# Platform
TARGET_BOARD_PLATFORM := mt6739

# Properties
TARGET_VENDOR_PROP += $(DEVICE_PATH)/configs/properties/vendor.prop

# Recovery
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/configs/fstab/fstab.mt6739
# mt6739-dbi scans out XRGB8888 only, which minui maps from BGRX_8888
TARGET_RECOVERY_PIXEL_FORMAT := BGRX_8888
BOARD_USES_FULL_RECOVERY_IMAGE := true

# SELinux
BOARD_VENDOR_SEPOLICY_DIRS += $(DEVICE_PATH)/sepolicy/vendor

# Verified boot (LK is unlocked and does not check AVB)
BOARD_AVB_ENABLE := false
