#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

ifeq ($(TARGET_DEVICE),m7)

define agm-m7-check-ramdisk-size
	size=$$(stat -c %s $(1)); \
	if [ $$size -gt $(AGM_M7_MAX_RAMDISK_SIZE) ]; then \
		echo "error: $(1) is $$size bytes, LK allows $(AGM_M7_MAX_RAMDISK_SIZE)" >&2; \
		exit 1; \
	fi
endef

AGM_M7_RAMDISK_CHECK := $(PRODUCT_OUT)/obj/PACKAGING/agm_m7_ramdisk_check.stamp
$(AGM_M7_RAMDISK_CHECK): $(INSTALLED_RAMDISK_TARGET)
	$(call agm-m7-check-ramdisk-size,$<)
	mkdir -p $(dir $@) && touch $@

ifneq ($(INSTALLED_BOOTIMAGE_TARGET),)
$(INSTALLED_BOOTIMAGE_TARGET): $(AGM_M7_RAMDISK_CHECK)
endif

ifneq ($(INSTALLED_RECOVERYIMAGE_TARGET),)
AGM_M7_RECOVERY_RAMDISK_CHECK := $(PRODUCT_OUT)/obj/PACKAGING/agm_m7_recovery_ramdisk_check.stamp
$(AGM_M7_RECOVERY_RAMDISK_CHECK): $(recovery_ramdisk)
	$(call agm-m7-check-ramdisk-size,$<)
	mkdir -p $(dir $@) && touch $@

$(INSTALLED_RECOVERYIMAGE_TARGET): $(AGM_M7_RECOVERY_RAMDISK_CHECK)
endif

endif
