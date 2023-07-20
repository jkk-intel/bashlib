#!/bin/bash

BASHLIB_HOME="${BASHLIB_HOME:="$HOME/.bashlib"}"
BASHLIB_LIB_DEFAULT="${BASHLIB_DEFAULT_LIB:=}"
BASHLIB_LIB_ALLOWLIST="${BASHLIB_LIB_ALLOWLIST:=}"

function should_alias() { if [[ "$ALIASES" == *" $1 "* ]]; then return 1; fi ; ALIASES="$ALIASES $1 "; }
should_alias expand_aliases && shopt -s expand_aliases
should_alias failfast && alias failfast='if [[ "$-" != *"e"* ]]; then set -e; trap "set +e" RETURN; fi'
should_alias failignore && alias failignore='if [[ "$-" == *"e"* ]]; then set +e; trap "set -e" RETURN; fi'

if [[ -z $BASHLIB_DEFAULT_FUNCTIONS_SET ]]; then
    function error() { while IFS= read -r LINE; do echo -e "# $LINE" >&2; done <<< "ERROR; $@"; exit 1; }
    function strindex() { local x="${1%%"$2"*}"; [[ "$x" = "$1" ]] && echo -1 || echo ${#x}; }
    function contains() { local x="${1%%"$2"*}"; [[ "$x" = "$1" ]] && echo '' || echo true; }
    function join_by { local IFS="$1"; shift; echo "$*"; }
    function split { IFS="$3" read -ra "$5" <<< "$1"; }
    function hashmap_get() { local ARR=$1 I=$2; local VAR="${ARR}_$I"; printf '%s' "${!VAR}"; }
    function lock() {
        failignore
        if [[ -z "$1" ]]; then return 1; fi
        local HASH="$(echo "$1" | shasum -a 256)"; HASH="${HASH:0:32}"
        local LOCKF="/tmp/$HASH.lock"
        local EXP="$2"; [[ -z "$EXP" ]] && EXP=60; (( EXP=EXP+$(date +%s) ));
        local LOCKER=
        if ( set -o noclobber; echo "$$:$EXP" > "$LOCKF" ) 2> /dev/null; then
            LOCKER=$(cat "$LOCKF" 2> /dev/null)
            if [[ "$LOCKER" == "$$:"* ]]; then echo true && return 0; fi
        fi
        LOCKER=$(cat "$LOCKF" 2> /dev/null)
        if [[ -n "$LOCKER" ]]; then
            function strindex() { local x="${1%%"$2"*}"; [[ "$x" = "$1" ]] && echo -1 || echo ${#x}; }
            local COLON_IDX=$(strindex "$LOCKER" ':')
            if [[ "$COLON_IDX" == '-1' ]]; then return 0; fi
            local LOCKER_PID=${LOCKER:0:$COLON_IDX}
            local LOCK_EXP=${LOCKER:(($COLON_IDX+1))}
            local KILL_OUTPUT="$(kill -s 0 "$LOCKER_PID" 2>&1 || true)"
            if [[ $(strindex "$KILL_OUTPUT" "No such") != '-1' ]] || (( LOCK_EXP-$(date +%s)<0 )); then
                rm -rf "$LOCKF" && echo $(lock "$1" "$2");
            fi
        fi
    }
    function unlock() {
        if [[ -z "$1" ]]; then return 1; fi
        local HASH="$(echo "$1" | shasum -a 256)"
        HASH="${HASH:0:32}"
        local pidf="/tmp/$HASH.lock"
        rm -rf "$pidf"
    }
    function trylock() {
        if [[ -z "$1" ]] || [[ -z "$2" ]]; then return 1; fi
        local START_TIME=$(date +%s)
        while [[ ! $(lock "$1") ]]; do
            sleep 0.2;
            if (( $(date +%s)-START_TIME>$2 )); then
                echo "unable to gain lock in ${2}s" 1>&2; return 1;
            fi
        done
    }
    BASHLIB_DEFAULT_FUNCTIONS_SET=true
fi

function bashlib() {
    failfast
    function fetch() {
        failfast
        function debug() { [[ ! $DEBUG ]] && return 0; while IFS= read -r LINE; do echo -e "# $LINE" >&2; done <<< "$@"; }
        local AFTER_FROM= LIB_SOURCE= NOCACHE_IMPORT= DEBUG= PACKAGES=()
        for ARG in "$@"; do
            if [[ $ARG == '-from' ]] || [[ $ARG == '--from' ]]; then AFTER_FROM=true; continue; fi
            if [[ $AFTER_FROM ]]; then
                if [[ -z "$LIB_SOURCE" ]]; then
                    LIB_SOURCE="$ARG"; LIB_SOURCE="${LIB_SOURCE:="$BASHLIB_LIB_DEFAULT"}";
                fi
                if [[ "$ARG" == *"-no-cache" ]]; then NOCACHE_IMPORT=true; fi
                if [[ "$ARG" == *"-debug" ]]; then DEBUG=true; fi
            else
                if [[ "$ARG" == "-"* ]]; then error "cannot provide import parameter like '$ARG' before '-from'"; fi
                PACKAGES+=("$ARG")
            fi
        done
        if [[ -z "$LIB_SOURCE" ]]; then LIB_SOURCE="$BASHLIB_LIB_DEFAULT"; fi
        for PKG_NAME_FULL in "${PACKAGES[@]}"; do
            local PKG_INFO=; split "$PKG_NAME_FULL" --delim ':' --into PKG_INFO
            local PKG_NAME="${PKG_INFO[0]}"; local PKG_VER="${PKG_INFO[1]}"; local PKG_BRANCH="${PKG_INFO[2]}"
            PKG_VER="${PKG_VER:="v1.0"}"; PKG_BRANCH="${PKG_BRANCH:="main"}"
            local LIB_DIR="$BASHLIB_HOME/$LIB_SOURCE/$PKG_BRANCH"
            local PKG_DIR="$LIB_DIR/$PKG_NAME/$PKG_VER"
            local CLONE_DIR="$BASHLIB_HOME/$LIB_SOURCE/.src"
            local PKG_FILE="$PKG_DIR/$PKG_NAME.sh"
            local PKG_FILE_REL="$PKG_NAME/$PKG_VER/$PKG_NAME.sh"
            if [[ -z "$NOCACHE_IMPORT" ]] && [[ -f "$PKG_FILE" ]] &&
                [[ "$(head -1 "$PKG_FILE")" != "# FETCH FAILED"* ]]; then
                echo "$PKG_FILE"; return 0;
            fi
            local START_TIME=$(date +%s)
            while [[ ! $(lock "git_clone-$LIB_SOURCE") ]]; do
                sleep 0.2;
                if [[ -f "$PKG_FILE" ]]; then
                    if [[ "$(head -1 "$PKG_FILE")" == "# FETCH FAILED"* ]]; then
                        echo "# ERROR; $LIB_SOURCE:$PKG_NAME_FULL" && return 1;
                    else
                        echo "$PKG_FILE"; return 0;
                    fi
                fi
                if (( $(date +%s)-START_TIME>7 )); then
                    error "could not resolve import source fetch lock ($LIB_SOURCE :: $PKG_NAME_FULL)"
                fi
            done
            debug "cloning $PKG_NAME"
            {
                mkdir -p "$PKG_DIR"; rm -rf "$CLONE_DIR"; mkdir -p "$CLONE_DIR";
                git clone https://github.com/$LIB_SOURCE.git --depth 1 "$CLONE_DIR"
                cd "$CLONE_DIR";
                git checkout $PKG_BRANCH;
                git reset --hard; git clean -ffdx;
                cp -r "$CLONE_DIR/"* "$LIB_DIR/"
            } >/dev/null 2>&1 || true
            unlock "git_clone-$LIB_SOURCE"
            if [[ -f "$PKG_FILE" ]] && [[ "$(head -1 "$PKG_FILE")" != "# FETCH FAILED"* ]]; then
                echo "$PKG_FILE"
            else 
                local ERROR_MSG="failed to fetch import source '$LIB_SOURCE' ($PKG_NAME_FULL)"
                printf "# FETCH FAILED\necho -e \"$ERROR_MSG\"\nexit 1" > "$PKG_FILE"
                echo "# ERROR; $LIB_SOURCE:$PKG_NAME_FULL"
                error "$ERROR_MSG"
            fi
        done
    }
    local ACTION="$1"; shift;
    if [[ "$ACTION" == "import" ]]; then
        local SOURCES=$(fetch "$@")
        while read SRC; do
            if [[ "$SRC" == "# ERROR; "* ]]; then
                echo "$SRC; package not found";
            elif [[ -f "$SRC" ]]; then
                source "$SRC"
            fi
        done <<< "$SOURCES"
    fi
}

function import() {
    bashlib import "$@"
}
