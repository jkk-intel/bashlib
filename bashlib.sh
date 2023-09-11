#!/bin/bash

[[ -n "$BASHLIB_SOURCED" ]] && return 0;
BASHLIB_SOURCED=true

set -TEeo pipefail

# bashlib
if [[ -n "$SHARED_DIR" ]]; then BASHLIB_HOME="$SHARED_DIR/.bashlib" ; fi
BASHLIB_HOME="${BASHLIB_HOME:="$HOME/.bashlib"}"
BASHLIB_LIB_DEFAULT="${BASHLIB_LIB_DEFAULT:=}"
BASHLIB_LIB_ALLOWLIST="${BASHLIB_LIB_ALLOWLIST:=}"
BASHLIB_DEBUG=true

# try catch utils
e= ; em= ; E= ; R= ;
__TCD=$(mktemp -d) # try-catch thrown error store dir
__TCA=() # try-catch subshells pid array
__TCL= # try-catch lineno
__TCF= # try-catch funcname
__TCS= # try-catch source
__TCL2= # try-catch lineno (depth 2)
__TCF2= # try-catch funcname (depth 2)
__TCS2= # try-catch source (depth 2)
__TCFS= # try-catch funcname & source
__TCDBG=() # try-catch debug stack trace
__FLOWCTL_HALTED=

function should_alias() { if [[ "$ALIASES" == *" $1 "* ]]; then return 1; fi ; ALIASES="$ALIASES $1 "; }
should_alias expand_aliases && shopt -s expand_aliases
should_alias __silent && alias __silent=' >/dev/null 2>&1 '
should_alias __bashlib && alias __bashlib='tiff; if [[ "$1" == "--bashlib" ]]; then echo true && return 0; fi'
should_alias __bashlib_fig && alias __bashlib='tifig; if [[ "$1" == "--bashlib" ]]; then echo true && return 0; fi'
should_alias failfast && alias failfast='[[ "$-" != *"e"* ]] && set -e && trap "set +e" RETURN'
should_alias failignore && alias failignore='[[ "$-" == *"e"* ]] && set +e && trap "set -e" RETURN'
should_alias ff && alias ff='failfast'
should_alias fig && alias fig='failignore'
should_alias tiff && alias tiff='local TIF=tiff; [[ "$-" != *"e"* ]] && local SAVED_E="set +e;" && set -e; local DEBUG_TRAP_SAVED="$(trap -p DEBUG)"; [[ -n "$DEBUG_TRAP_SAVED" ]] && trap - DEBUG; trap "eval \"\$SAVED_E\$DEBUG_TRAP_SAVED\"" RETURN'
should_alias tifig && alias tifig='local TIF=tifig; [[ "$-" == *"e"* ]] && local SAVED_E="set -e;" && set +e; local DEBUG_TRAP_SAVED="$(trap -p DEBUG)"; [[ -n "$DEBUG_TRAP_SAVED" ]] && trap - DEBUG; trap "eval \"\$SAVED_E\$DEBUG_TRAP_SAVED\"" RETURN'
should_alias e && alias e='; [[ "$e" ]] && '
should_alias se && alias se='echo -e "$E"'
should_alias eout && alias eout='__throw "$(caller_trace)" eout || return 1 2>/dev/null || exit 1'
should_alias skip && alias skip='return 0 2>/dev/null || exit 0'
should_alias try && alias try='trap_halt; PID=$(pid); e= ; em= ; E= ; R= ; __trypush $PID; trap_resume; set +e; (trap_err_push; set -e; PID=$(pid);'
should_alias catch && alias catch='); R="$?"; trap_halt; __trypop; __error_set "$__TCD/$PID" "$R"; set -e; trap_resume '
should_alias resolved && alias resolved='; [[ true ]] && '
should_alias finally && alias finally='; [[ true ]] && '
should_alias throw && alias throw='__throw "$(caller_trace)"'
should_alias debug_line && alias debug_line='echo "    at ${FUNCNAME[0]} (${BASH_SOURCE[0]}:$LINENO)"'
should_alias trap_halt && alias trap_halt='FLOWCTL_HALTED=1'
should_alias trap_resume && alias trap_resume='FLOWCTL_HALTED=""'
should_alias trap_err_push && alias trap_err_push='trap "RC=\$?; trap - DEBUG; exit_error_trap EXIT \$RC \"\" \"\$(debug_line)\";" EXIT; trap "RC=\$?; trap - DEBUG; exit_error_trap ERR \$RC \"\" \"\$(debug_line)\";" ERR; trap "debug_trap \$LINENO \"\${FUNCNAME[0]}\" \"\${BASH_SOURCE[0]}\"" DEBUG'
function pid() { exec bash -c "echo \$PPID | xargs"; }
function ppid() { local PID=$(pid); PID=$(ps -o ppid= -p "$PID" | xargs); ps -o ppid= -p "$PID" | xargs; }
function __trypush() { __TCA+=("$1") || true; }
function __trytop() { echo "${__TCA[${#__TCA[@]}-1]}" || true; }
function __trypop() { unset '__TCA[${#__TCA[@]}-1]' || true; }
function __error_set() {
    local F="$1"; local RC="$2";
    [[ -f "$F" ]] && { em="$(cat "$F")"; e="$(echo -e "$em" | head -n 1)"; E="ERROR($RC): $em"; rm -rf "$F"; }
}
function __throw() {
    trap_halt;
    local F="$__TCD/$(__trytop)";
    local IS_ROOT=1; [[ "$(pid)" != "$PID_ROOT" ]] && IS_ROOT= ;
    echo -e "$2\n$1" > "$F"; local __TC="1"; [[ -n "$3" ]] && __TC="$3";
    THROWN=true;
    [[ -n "$IS_ROOT" ]] && { __error_set "$F" "$__TC"; se; }
    trap_resume;
    return $__TC;
}
function caller_trace() {
    trap_halt; fig;
    local FRAME=0; local TRACE= ; local TRACE_SPLIT=
    [[ -n "$2" ]] && echo "$2"; [[ -n "$3" ]] && echo "$3";
    while TRACE="$(caller $FRAME)"; do
        str_split "$TRACE" --delim ' ' --into TRACE_SPLIT
        local FILE="${TRACE_SPLIT[2]}";
        local LINE="${TRACE_SPLIT[0]}";
        [[ "${FILE:0:1}" != '/' ]] && FILE="$(pwd)/$FILE";
        if [[ -z "$1" ]] || [[ "$FRAME" -ge "$1" ]]; then
            echo "    at ${TRACE_SPLIT[1]} ($FILE:$LINE)";
        fi
        let "FRAME++";
    done
    trap_resume;
}
function debug_trap() {
    [[ "$FLOWCTL_HALTED" ]] && return;
    [[ "${BASH_COMMAND:0:9}" == 'local TIF=' ]] && return;
    [[ "${BASH_COMMAND:0:14}" == 'FLOWCTL_HALTED' ]] && return;
    local DELIM="$(str_index "$BASH_COMMAND" ' ')"
    local CMD_HEAD=
    if [[ "$DELIM" == '-1' ]]; then
        CMD_HEAD="$BASH_COMMAND";
    else
        CMD_HEAD="${BASH_COMMAND:0:$DELIM}";
    fi
    local FUNC="$2"; [[ -z "$FUNC" ]] && FUNC='main';
    local FUNC_CHANGED= ; [[ "$__TCFU" != "$FUNC" ]] && FUNC_CHANGED=true
    local LINE_PROGRESSING=; [[ -n "$__TCLU" ]] && (( "$__TCLU" < $1 )) && LINE_PROGRESSING=true
    __TCLU="$1"; __TCFU="$FUNC"; __TCSU="$3"; [[ "${__TCSU:0:1}" != '/' ]] && __TCSU="$PWD/$__TCSU";
    local DBGLINE="    at $__TCFU ($__TCSU:$__TCLU)"
    if [[ -n "$FUNC_CHANGED" ]]; then
        [[ -n "$BASHLIB_DEBUG" ]] && echo -e "[$PID] [FUNC_CHANGED ] ($BASH_COMMAND) $DBGLINE" 1>&2
        __TCDBG+=("$DBGLINE")
    elif [[ -n "$LINE_PROGRESSING" ]]; then
        [[ -n "$BASHLIB_DEBUG" ]] && echo -e "[$PID] [LINE PROGRESS] ($BASH_COMMAND) $DBGLINE" 1>&2
        local IDX="${#__TCDBG[@]}"; let "IDX--";
        if [[ "$IDX" == '-1' ]]; then __TCDBG[0]="$DBGLINE"; else __TCDBG[$IDX]="$DBGLINE"; fi
    fi
    if [[ "$CMD_HEAD" == 'return' ]] || [[ "$CMD_HEAD" == 'exit' ]]; then
        local TCL="$__TCLU"; local TCF="$__TCFU"; local TCS="$__TCSU"; local TCFS="$TCF $TCS";
        if [[ "$__TCFS" != "$TCFS" ]]; then
            __TCL2="$__TCL"; __TCF2="$__TCF"; __TCS2="$__TCS";
            __TCL="$TCL"; __TCF="$TCF"; __TCS="$TCS"; __TCFS="$TCFS";
        else
            __TCL="$TCL"; __TCF="$TCF"; __TCS="$TCS"; __TCFS="$TCFS";
        fi
    fi
}
function exit_error_trap() {
    [[ "$FLOWCTL_HALTED" ]] && return;
    local KIND="$1"; local RC="$2"; local IS_ROOT=1; [[ "$(pid)" != "$PID_ROOT" ]] && IS_ROOT= ;
    [[ -n "$BASHLIB_DEBUG" ]] && echo -e "[$PID] [EXIT/ERR TRAP] ROOT=$IS_ROOT THROWN=$THROWN" \
                                         "$1 $2 $3 $4 $5 $6\n$(caller_trace)" 1>&2 || true
    if [[ -n "$THROWN" ]]; then return; fi
    if [[ "$__TCF2" == '__throw' ]]; then return; fi
    trap - "$KIND"
    if [[ "$KIND" == 'ERR' ]] && [[ -z "$IS_ROOT" ]]; then
        local DEEPER_TRACE=
        # intentional error with return or exit
        if [[ -n "$__TCF2" ]]; then
            DEEPER_TRACE="    at $__TCF2 ($__TCS2:$__TCL2)";
            __throw "$(caller_trace 2 "$DEEPER_TRACE" "${__TCDBG[${#__TCDBG[@]}-3]}")" 'error' || true
        else # unintentional error without return or exit
            DEEPER_TRACE="${__TCDBG[${#__TCDBG[@]}-1]}";
            __throw "$(caller_trace 2 "$DEEPER_TRACE")" 'error' || true
        fi
    elif [[ "$KIND" == 'EXIT' ]] && [[ "$RC" != '0' ]]; then
        __throw "$(caller_trace 1)" 'error' || true
    fi
}

function error() { 
    __bashlib
    if [[ "$1" == "-m" ]]; then local NO_EXIT=true; shift; fi
    while IFS= read -r LINE; do echo -e "# $LINE" >&2; done <<< "ERROR; $@";
    [[ $NO_EXIT ]] || return 1;
}
function str_index() {
    __bashlib
    local x="${1%%"$2"*}";
    [[ "$x" = "$1" ]] && echo -1 || echo ${#x};
}
function str_contains() {
    __bashlib
    local x="${1%%"$2"*}"; [[ "$x" = "$1" ]] && echo '' || echo true;
}
function str_join_by {
    local IFS="$1"; shift; echo "$*";
}
function str_split { IFS="$3" read -ra "$5" <<< "$1"; }
function hashmap_get() { local ARR=$1 I=$2; local VAR="${ARR}_$I"; printf '%s' "${!VAR}"; }
function pos_int() { case "$1" in ''|*[!0-9]*) ;; *) echo true ;; esac }
function lock() {
    __bashlib_fig
    if [[ -z "$1" ]]; then return 1; fi
    local HASH="$(echo "$1" | shasum -a 256)"; HASH="${HASH:0:32}"
    local LOCKDIR="$BASHLIB_LOCKDIR" ; if [[ -z "$LOCKDIR" ]]; then LOCKDIR="$SHARED_DIR"; fi
    local LOCKF="$LOCKDIR/tmp/$HASH.lock" ; mkdir -p "$LOCKDIR/tmp"
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
    __bashlib
    if [[ -z "$1" ]]; then return 1; fi
    local HASH="$(echo "$1" | shasum -a 256)"
    HASH="${HASH:0:32}"
    local LOCKDIR="$BASHLIB_LOCKDIR" ; if [[ -z "$LOCKDIR" ]]; then LOCKDIR="$SHARED_DIR"; fi
    local pidf="$LOCKDIR/tmp/$HASH.lock"
    rm -rf "$pidf"
}
function trylock() {
    __bashlib
    if [[ -z "$1" ]] || [[ -z "$2" ]]; then return 0; fi
    local SIGNAL_FILE="$3"
    local START_TIME=$(date +%s)
    while [[ ! $(lock "$1" "$2") ]]; do
        sleep 0.2;
        if (( $(date +%s)-START_TIME>$2 )); then
            echo "unable to gain lock in ${2}s" 1>&2; return 0;
        fi
        if [[ -f "$SIGNAL_FILE" ]]; then
            echo "already_handled"
            break
        fi
    done
    echo "should_handle"
}
function killtree() {
    __bashlib
    if [[ "$1" != "-"* ]]; then error "Usage: killtree -SIGNAL <PID>"; fi
    pkill "$1" -P "$2" & local CHPID= ; while IFS= read -r CHPID; do
        [[ "$CHPID" ]] && [[ "$CHPID" != "$2" ]] && killtree "$1" "$CHPID"
    done <<< "$(pgrep -P "$2" || true)"
}
function timeout() {
    __bashlib
    local TIMEOUT="$1" GRACE_PERIOD=; shift;
    if [[ $(pos_int "$1") ]]; then GRACE_PERIOD="$1"; shift; fi
    local EXPR="$@"; local EVAL_PID= ; (
        eval "$EXPR &"; EVAL_PID=$!
        ( sleep $TIMEOUT; error -m "Timed out in ${TIMEOUT}s: $EXPR"; killtree -SIGTERM $EVAL_PID __silent) &
        [[ -n "$GRACE_PERIOD" ]] && ( sleep $((TIMEOUT+GRACE_PERIOD)); killtree -SIGKILL $EVAL_PID __silent) &
        wait $EVAL_PID
    )
}

function bashlib() {
    tiff
    function fetch() {
        tiff
        function debug() { [[ ! $DEBUG ]] && return 0; while IFS= read -r LINE; do echo -e "# $LINE" >&2; done <<< "$@"; }
        local AFTER_FROM= LIB_SOURCE= NOCACHE_IMPORT= DEBUG= PACKAGES=()
        for ARG in "$@"; do
            if [[ $ARG == '-from' ]] || [[ $ARG == '--from' ]]; then AFTER_FROM=true; continue; fi
            if [[ "$ARG" == *"-no-cache" ]]; then NOCACHE_IMPORT=true && continue; fi
            if [[ "$ARG" == *"-debug" ]]; then DEBUG=true && continue; fi
            if [[ $AFTER_FROM ]]; then
                if [[ -z "$LIB_SOURCE" ]]; then
                    LIB_SOURCE="$ARG"; LIB_SOURCE="${LIB_SOURCE:="$BASHLIB_LIB_DEFAULT"}";
                fi
            else
                if [[ "$ARG" == "-"* ]]; then error "cannot provide import parameter like '$ARG' before '-from'"; fi
                PACKAGES+=("$ARG")
            fi
        done
        if [[ -z "$LIB_SOURCE" ]]; then LIB_SOURCE="$BASHLIB_LIB_DEFAULT"; fi
        if [[ "$LIB_SOURCE" == 'local' ]]; then return; fi
        for PKG_NAME_FULL in "${PACKAGES[@]}"; do
            local PKG_INFO=; str_split "$PKG_NAME_FULL" --delim ':' --into PKG_INFO
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
                local TOKEN_HEADER=
                if [[ $BASHLIB_GITHUB_ACCESS ]]; then
                    local TOKEN_BASE64="$(printf "x-access-token:$BASHLIB_GITHUB_ACCESS" | base64)"
                    TOKEN_HEADER="-c http.extraHeader='Authorization: basic $TOKEN_BASE64'"
                fi
                git $TOKEN_HEADER clone https://github.com/$LIB_SOURCE.git --depth 1 "$CLONE_DIR"
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
    tiff;
    bashlib import "$@"
}

PID=$(pid); PID_ROOT=$(pid); __trypush $PID;
trap "RC=\$?; trap - DEBUG; exit_error_trap EXIT \$RC \"\$(debug_line)\" ROOT;" EXIT;
trap "RC=\$?; trap - DEBUG; exit_error_trap ERR \$RC \"\$(debug_line)\" ROOT;" ERR;
trap "debug_trap \$LINENO \"\${FUNCNAME[0]}\" \"\${BASH_SOURCE[0]}\"" DEBUG;
