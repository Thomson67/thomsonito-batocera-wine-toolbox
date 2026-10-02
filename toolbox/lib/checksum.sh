#!/bin/bash
verify_sha256() {
    local file="$1" expected="$2" actual
    actual="$(sha256sum "$file" | awk '{print $1}')"
    [ "$actual" = "$expected" ]
}
