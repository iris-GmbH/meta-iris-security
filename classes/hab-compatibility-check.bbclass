# SPDX-License-Identifier: MIT
# Copyright (C) 2025 iris-GmbH infrared & intelligent sensors

# Helper functions to check csf/srk header of image artifact at build time

inherit hab

DEPENDS += "hab-csf-parser-native"

# Check is only implemented for HABv4
check_srk_compatibility() {
    :
}

check_srk_compatibility:hab4() {
    check_csf_compatibility "$1"
}

check_csf_compatibility() {
    local signed_image="$1"
    rm -f output/SRKTable.bin
    csf_parser -s "${signed_image}" || true
    if [ ! -f output/SRKTable.bin ]; then
        bbfatal "generated ${signed_image} is not compatible with csf_parser and update on locked boards will not be accepted"
    fi
}
