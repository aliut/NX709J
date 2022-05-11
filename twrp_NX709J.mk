#
# Copyright (C) 2022 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit some common Lineage stuff.
#$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Inherit from NX709J device
$(call inherit-product, device/nubia/NX709J/device.mk)

PRODUCT_DEVICE := NX709J
PRODUCT_NAME := lineage_NX709J
PRODUCT_BRAND := nubia
PRODUCT_MODEL := NX709J
PRODUCT_MANUFACTURER := nubia

PRODUCT_GMS_CLIENTID_BASE := android-zte

PRODUCT_BUILD_PROP_OVERRIDES += \
    PRIVATE_BUILD_DESC="NX709J-user 12 SKQ1.211019.001 eng.nubia.20220111.205659 release-keys"

BUILD_FINGERPRINT := nubia/NX709J/NX709J:12/SKQ1.211019.001/eng.nubia.20220111.205659:user/release-keys
