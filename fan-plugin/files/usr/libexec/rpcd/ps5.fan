#!/bin/sh
case "$1" in
    list)
        echo '{"status":{},"apply":{"mode":"","target":0}}'
        ;;
    call)
        case "$2" in
            status) exec /usr/libexec/ps5-fanctl status ;;
            apply)
                . /usr/share/libubox/jshn.sh
                IFS= read -r request
                json_load "$request" || { echo '{"ok":false,"error":"请求格式错误。"}'; exit 0; }
                json_get_var mode mode
                json_get_var target target
                exec /usr/libexec/ps5-fanctl apply "$mode" "$target"
                ;;
        esac
        ;;
esac
