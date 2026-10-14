#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/generic_no_telephony.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/telephony.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/languages_full.mk)

# Same as common_mini_go_phone.mk, with AOSP telephony for mobile data only (no SMS or calls yet)
PRODUCT_TYPE := go
$(call inherit-product, vendor/lineage/config/common_mobile_mini.mk)

PRODUCT_IS_GO := true
$(call inherit-product, device/agm/m7/device.mk)

PRODUCT_NAME := lineage_m7
PRODUCT_DEVICE := m7
PRODUCT_BRAND := AGM
PRODUCT_MANUFACTURER := AGM
PRODUCT_MODEL := M7

PRODUCT_VENDOR_PROPERTIES += \
    ro.soc.manufacturer=MediaTek \
    ro.soc.model=MT6739
