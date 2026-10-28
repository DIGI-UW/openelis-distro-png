#!/bin/sh
# Shared by Compose initialization and the operator's password-reset helper.
validate_admin_password() {
    [ -n "${1:-}" ] && [ "$1" != 'adminADMIN!' ] || {
        echo 'Set a unique OE_ADMIN_PASSWORD in .env.' >&2; return 1;
    }
    [ "${#1}" -ge 8 ] || { echo 'OE_ADMIN_PASSWORD must have at least 8 characters.' >&2; return 1; }
    case "$1" in *[!A-Za-z0-9_%\$\#!]*)
        echo 'OE_ADMIN_PASSWORD permits only letters, digits, underscore and % $ # !.' >&2; return 1 ;;
    esac
    _png_classes=0
    case "$1" in *[a-z]*) _png_classes=$((_png_classes + 1)) ;; esac
    case "$1" in *[A-Z]*) _png_classes=$((_png_classes + 1)) ;; esac
    case "$1" in *[0-9]*) _png_classes=$((_png_classes + 1)) ;; esac
    case "$1" in *[%\$\#!]*) _png_classes=$((_png_classes + 1)) ;; esac
    [ "$_png_classes" -ge 3 ] || {
        echo 'OE_ADMIN_PASSWORD needs three of lowercase, uppercase, digits and special characters.' >&2; return 1;
    }
    unset _png_classes
}
