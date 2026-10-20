REQUIRE_IMAGE_METADATA=1
platform_check_image() {
    echo 'PS5 uses a dedicated patched kernel. Generic OpenWrt sysupgrade is disabled.' >&2
    echo 'Back up configuration and use a newly built PS5 external-drive image.' >&2
    return 1
}
