#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/agm/m7

# Options for device/mainline/common. They must come before its makefile.
TARGET_AUDIO_HAL := mainline
TARGET_AUDIO_MAINLINE_UCM_PROFILES := none
TARGET_BLUETOOTH_HAL := none
TARGET_FOLLOWS_LATEST_SHIPPING_API_LEVEL := true
TARGET_FOLLOWS_LATEST_VINTF_TARGET_LEVEL := true
TARGET_GRAPHICS := swiftshader
TARGET_GRAPHICS_ALLOCATOR_HAL := minigbm-upstream
TARGET_MINIGBM_PLATFORM := generic
# TODO: drm_hwcomposer needs ABGR8888 on the mt6739-dbi plane, else use drmfb-composer (see DESIGN.md)
TARGET_GRAPHICS_COMPOSER_HAL := drm_hwcomposer
TARGET_HAS_BATTERY := true
# TODO: check if the phone has a vibration motor
TARGET_HAS_VIBRATOR := false
TARGET_HEALTH_HAL := default-aidl
TARGET_SENSORS_HAL := none
TARGET_SUPPORTS_SUSPEND := false
TARGET_USB_HAL := lineage-basic

$(call inherit-product, device/mainline/common/mainline_common.mk)

# Bootanimation
TARGET_SCREEN_WIDTH := 240
TARGET_SCREEN_HEIGHT := 320

# Dalvik heap
$(call inherit-product, frameworks/native/build/phone-xhdpi-1024-dalvik-heap.mk)

# Dynamic partitions
PRODUCT_USE_DYNAMIC_PARTITIONS := true
PRODUCT_BUILD_SUPER_PARTITION := true
PRODUCT_USE_DYNAMIC_PARTITION_SIZE := true

# Fstab
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/configs/fstab/fstab.mt6739:$(TARGET_COPY_OUT_RAMDISK)/fstab.mt6739 \
    $(DEVICE_PATH)/configs/fstab/fstab.mt6739:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.mt6739

# Init
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/configs/init/init.mt6739.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/hw/init.mt6739.rc \
    $(DEVICE_PATH)/configs/init/ueventd.mt6739.rc:$(TARGET_COPY_OUT_VENDOR)/etc/ueventd.mt6739.rc \
    $(DEVICE_PATH)/configs/init/init.recovery.mt6739.rc:$(TARGET_COPY_OUT_RECOVERY)/root/init.recovery.mt6739.rc

PRODUCT_PACKAGES += \
    use_memfd.rc

# Input
PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/configs/input/mt6779-keypad.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/mt6779-keypad.idc \
    $(DEVICE_PATH)/configs/input/mt6779-keypad.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/mt6779-keypad.kl \
    $(DEVICE_PATH)/configs/input/mt6779-keypad.kcm:$(TARGET_COPY_OUT_VENDOR)/usr/keychars/mt6779-keypad.kcm \
    $(DEVICE_PATH)/configs/input/mtk-pmic-keys.kl:$(TARGET_COPY_OUT_VENDOR)/usr/keylayout/mtk-pmic-keys.kl

# TODO: the touch input name comes from the controller (edt-ft5x06); read it from /proc/bus/input/devices
# PRODUCT_COPY_FILES += $(DEVICE_PATH)/configs/input/<touch name>.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/<touch name>.idc

# Kernel
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

# Overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(DEVICE_PATH)/overlay

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.faketouch.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.faketouch.xml \
    frameworks/native/data/etc/android.hardware.touchscreen.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.xml

# Properties
# apexd activates all APEXes at once; ueventd needs more than the 1 s default per dm device
PRODUCT_VENDOR_PROPERTIES += \
    apexd.config.dm_create.timeout=10000 \
    ro.sf.lcd_density=120

PRODUCT_PACKAGES += \
    mt6739-wlan-nvram.bin

# Recovery
PRODUCT_BUILD_RECOVERY_IMAGE := true

# Scoped storage
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(DEVICE_PATH) \
    kernel/mainline/configs

# Wi-Fi
# TODO: Wi-Fi HAL choice and the mt6739-wlan module load order (see DESIGN.md)
PRODUCT_PACKAGES += \
    android.hardware.wifi-service

# Proprietary files (Wi-Fi/CONSYS firmware, rgx.fw.signed), extracted from the stock vendor partition
$(call inherit-product-if-exists, vendor/agm/m7/m7-vendor.mk)
