# SPDX-License-Identifier: MIT
# Copyright (C) 2025 iris-GmbH infrared & intelligent sensors

# Class to extend fitimage recipes with HAB signing
# Set FITIMAGE_IMAGE_NAME and FITIMAGE_IMAGE_LINK_NAME!

inherit hab hab-compatibility-check

SIGNED_EXT ?= "signed"
CSF_CFG ?= "${HAB_DIR}/csf.cfg"
SIGNDIR ?= "${S}/sign"

SRC_URI:append = " file://${CSF_CFG}"

DEPENDS:append = " \
    cst-native \
    cst-signer-native \
    perl-native \
"

DEPENDS:append:ahab = "imx-mkimage-native"

FITLOADADDR ?= ""
FITLOADADDR:ahab ?= "0x80400000"
FITLOADADDR:hab4 ?= "0x48000000"

do_prepare_fitimage() {
    mkdir -p "${SIGNDIR}"
    cp "${B}/fitImage" "${SIGNDIR}/fitImage"
}

do_prepare_fitimage:append:ahab() {
    cd ${SIGNDIR}
    mkimage_imx8 -soc IMX9 -c -ap fitImage a55 ${FITLOADADDR} -out fitImage-ivt
    mv fitImage-ivt fitImage
}

do_prepare_fitimage:append:hab4() {
    attach_ivt ${SIGNDIR}/fitImage
    mv ${SIGNDIR}/fitImage-ivt ${SIGNDIR}/fitImage
}

attach_ivt() {
    if [ -z "${FITLOADADDR}" ]; then
        bbfatal "FITLOADADDR is not set!"
    fi

    IMAGE_SIZE="`wc -c < ${1}`"
    get_align_size_emit_file get_align_size.pl
    genivt_emit_file imx6-genIVT.pl
    ALIGNED_SIZE="$(perl -w get_align_size.pl ${IMAGE_SIZE})"
    objcopy -I binary -O binary --pad-to ${ALIGNED_SIZE} --gap-fill=0x00 ${1} ${1}-pad
    perl -w imx6-genIVT.pl ${FITLOADADDR} `printf "0x%x" ${ALIGNED_SIZE}`
    cat ${1}-pad ivt.bin > ${1}-ivt
    rm -f ${1}-pad
}

get_align_size_emit_file() {
	cat << 'EOF' > ${1}
use strict;
my $image_size = $ARGV[0];
my $aligned_size = (($image_size + 0x1000 - 1)  & ~ (0x1000 - 1));
print  "$aligned_size\n";
EOF
}

genivt_emit_file() {
	cat << 'EOF' > ${1}
use strict;
my $loadaddr = hex(shift);
my $img_size = hex(shift);

my $entry = $loadaddr;
my $ivt_addr = $loadaddr + $img_size;
my $csf_addr = $ivt_addr + 0x20;

open(my $out, '>:raw', 'ivt.bin') or die "Unable to open: $!";
print $out pack("V", 0x412000D1); # IVT Header
print $out pack("V", $entry); # Jump Location
print $out pack("V", 0x0); # Reserved
print $out pack("V", 0x0); # DCD pointer
print $out pack("V", 0x0); # Boot Data
print $out pack("V", $ivt_addr); # Self Pointer
print $out pack("V", $csf_addr); # CSF Pointer
print $out pack("V", 0x0); # Reserved
close($out);
EOF
}

addtask do_prepare_fitimage before do_deploy after do_fitimage

do_sign_fitimage() {
    if [ ! -f ${SIGNDIR}/csf.cfg ]; then
        install -m 0755 ${CSF_CFG} ${SIGNDIR}/csf.cfg
    fi

    # Generate signed fitimage using cst_signer
    cd "${SIGNDIR}"
    CST_EXE_PATH=cst CST_PATH=${HAB_DIR} cst_signer -d -i ${SIGNDIR}/fitImage -c ${SIGNDIR}/csf.cfg

    check_srk_compatibility "${SIGNDIR}/signed-fitImage"
}

addtask do_sign_fitimage before do_deploy after do_prepare_fitimage

do_deploy:append() {
    FITIMAGE_NAME=$(basename $(readlink -f ${DEPLOYDIR}/${FITIMAGE_IMAGE_LINK_NAME}))

    install -m 0644 ${SIGNDIR}/signed-fitImage ${DEPLOYDIR}/${FITIMAGE_NAME}.${SIGNED_EXT}

    cd ${DEPLOYDIR}
    ln -sf ${FITIMAGE_NAME}.${SIGNED_EXT} ${FITIMAGE_IMAGE_LINK_NAME}.${SIGNED_EXT}
}
