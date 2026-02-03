# SPDX-License-Identifier: MIT
# Copyright (C) 2026 iris-GmbH infrared & intelligent sensors

# This class extends the verity image (image_types_verity.bbclass) with roothash
# signing and verity image zipping
# Set ROOTHASH_DM_VERITY_SALT and ROOTHASH_SIGNING_PRIVATE_KEY to respective files

inherit image_types_verity

python () {
    if 'verity' not in d.getVar('IMAGE_FSTYPES'):
        return

    # Reduce the overhead factor to 1.1
    # free space in RO-Rootfs is useless, but yocto does not consider filesystem overhead
    d.setVar('IMAGE_OVERHEAD_FACTOR', '1.1')

    verity_base = d.getVar('VERITY_IMAGE_FSTYPE')

    # Add custom tasks
    bb.build.addtask('do_compress_verity_image', 'do_image_complete', 'do_image_verity', d)
    d.prependVarFlag('do_compress_verity_image', 'postfuncs', 'create_symlinks ')
    d.appendVarFlag('do_compress_verity_image', 'subimages', ' ' + verity_base + '.verity.gz')

    bb.build.addtask('do_sign_roothash', 'do_image_complete', 'do_image_verity', d)
    d.prependVarFlag('do_sign_roothash', 'postfuncs', 'create_symlinks ')
    d.appendVarFlag('do_sign_roothash', 'subimages', ' ' + ' '.join(verity_base + i for i in [".roothash", ".roothash.signature"]))
}

# Tell bitbake to track dmverity related files and to reparse the recipe when they change
SRC_URI += "\
    file://${ROOTHASH_DM_VERITY_SALT} \
    file://${ROOTHASH_SIGNING_PRIVATE_KEY} \
"

python do_image_verity:prepend () {
    # We need to open an external file (ROOTHASH_DM_VERITY_SALT read into VERITY_SALT). Setting these variables in the
    # parsing phase with an anonymous python function leads to "basehash/taskhash changed" errors. So we prepend these
    # steps here to the do_image_verity() function.

    # read dm-verity salt to variable
    d.setVar('VERITY_SALT', open(d.getVar('ROOTHASH_DM_VERITY_SALT'), 'r').read().strip())

    # Set HASHDEV_SUFFIX so the verity image class creates a seperate hashdevice image
    d.setVar('VERITY_IMAGE_HASHDEV_SUFFIX', '.hashdevice')
}

# DEPEND on openssl and gzip
do_compress_verity_image[depends] += "pigz-native:do_populate_sysroot"
do_sign_roothash[depends] += "openssl-native:do_populate_sysroot"

do_compress_verity_image () {
    VERITY_BASE_NAME=$(readlink -f "${VERITY_INPUT_IMAGE}")
    # Compress verity image, unfortunately "verity.gz" does not work in IMAGE_FSTYPES as verity does not utilize the 
    # image creation core logic
    # Command copied from poky - image_types.bbclass - CONVERSION_CMD:gz
    gzip -f -9 -n -c --rsyncable ${VERITY_BASE_NAME}.verity > ${VERITY_BASE_NAME}.verity.gz
}

do_sign_roothash() {
    VERITY_BASE_NAME=$(readlink -f "${VERITY_INPUT_IMAGE}")

    # write roothash to image directory
    verity_params="${VERITY_BASE_NAME}.verity-params"
    roothashfile="${VERITY_BASE_NAME}.roothash"
    sed -ne '/VERITY_ROOT_HASH/s/VERITY_ROOT_HASH=//p' "${verity_params}" > "${roothashfile}"

    # sign roothash and write signature to image directory
    roothash_signature_file="${roothashfile}.signature"
    if ! openssl dgst -sha256 -sign "${ROOTHASH_SIGNING_PRIVATE_KEY}" -out "${roothash_signature_file}" "${roothashfile}"
    then
        bbfatal "Signing roothash failed"
        exit 1
    fi
}
