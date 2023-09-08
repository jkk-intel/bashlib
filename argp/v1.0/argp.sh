#!/bin/bash

function argp() {
    failfast
    function setdef() {
        failfast
        local ACTION="$1"; shift;
        local PARAMS=()
        local PARAMS_SECTION_ENDED=
        local VAR_NAME=
        local ALLOWED_KEYWORDS=" required number integer string boolean positive negative boollike "
        local PARAM_SPECS=
        local PARAM_DEFAULT="__ARGPARSE_PARAM_DEFAULT_DEFAULT__"
        local ARG=
        for ARG in "$@"; do
            if [[ -z "$PARAMS_SECTION_ENDED" ]] && [[ "${ARG:0:1}" == "-" ]]; then
                PARAMS+=("$ARG")
            else
                if [[ -z "$PARAMS_SECTION_ENDED" ]]; then
                    PARAMS_SECTION_ENDED=true
                    VAR_NAME="$ARG"
                    continue
                fi
                if [[ $(contains "$ALLOWED_KEYWORDS" " $ARG ") ]]; then
                    PARAM_SPECS="${PARAM_SPECS}($ARG) "
                elif [[ $(strindex "$ARG" "default:") == 0 ]]; then
                    PARAM_DEFAULT="$ARG"
                else
                    error "unrecognized parameter spec '$ARG'"
                fi
            fi
        done
        local PARAM_DEF="$(join_by ',' "${PARAMS[@]}")"
        if [[ -z "$PARAM_DEF" ]]; then
            error "received no flag or longhand param definition" \
                  "(while handling '$@')"
        fi
        if [[ -z "$ARG_DEFS" ]]; then
            ARG_DEFS=()
        fi
        ARG_DEFS+=("$ACTION; $PARAM_DEF; $VAR_NAME; $PARAM_SPECS; $PARAM_DEFAULT");
    }
    local ACTION="$1"; shift || error "argp requires at least one argument";
    if [[ "$ACTION" == "flag" ]]; then setdef FLAG "$@"; return 0; fi
    if [[ "$ACTION" == "param" ]]; then setdef PARAM "$@"; return 0; fi
    if [[ "$ACTION" == "hybrid" ]]; then setdef HYBRID "$@"; return 0; fi
    if [[ "$ACTION" == "passthru" ]]; then setdef PASSTHRU "$@"; return 0; fi
    if [[ "$ACTION" == "passthru_flag" ]]; then setdef PASSTHRU_FLAG "$@"; return 0; fi

    function parse() {
        failfast
        local ARGS=
        function output() { echo -e "$@"; }
        function debug() { 
            if [[ -z "$DEBUG" ]]; then return 0; fi
            local MSG="$@"; while IFS= read -r LINE; do echo -e "# $LINE"; done <<< "$@"
        }
        output "#!/bin/bash"
        local YELLOW='\033[0;33m'
        local CYAN='\033[0;36m'
        local NC='\033[0m'
        local SAFE_ASSIGN="safe_assign"
        local VAR_ARRAY_INFO=
        local ARG_SETTERS=()
        local ARG_DEFAULTS=()
        local ARG_PASSTHRU=()
        local ARG_PASSTHRU_VAR_NAMES=()
        local ARG_PASSTHRU_VALUE_SETTERS=()
        function safe_assign_op() {
            local VAR_NAME="$1"
            local VAR_VALUE="$2"
            local IS_ARRAY_PUSH="$3"
            if [[ ! $(contains "$VAR_VALUE" "'") ]]; then
                echo ""
                debug "assigning [${YELLOW} $VAR_NAME ${NC}]"
                if [[ $IS_ARRAY_PUSH ]]; then
                    echo "$VAR_NAME+=('$VAR_VALUE')"
                else
                    echo "$VAR_NAME='$VAR_VALUE'"
                fi
            else
                local DELIM_UID="$(openssl rand -base64 24)"
                DELIM_UID="${DELIM_UID//+/z}"
                DELIM_UID="${DELIM_UID////z}"
                local MULTILINE_DELIM="____EOF_${DELIM_UID}____"
                local TEMP_VAR_NAME="TMP_${DELIM_UID}"
                echo ""
                debug "safely assigning [${YELLOW} $VAR_NAME ${NC}]"
                echo "$SAFE_ASSIGN ${TEMP_VAR_NAME} << '${MULTILINE_DELIM}'"
                echo "$VAR_VALUE"
                echo "$MULTILINE_DELIM"
                if [[ $IS_ARRAY_PUSH ]]; then
                    echo "$VAR_NAME+=(\"\${${TEMP_VAR_NAME}%?}\")"
                else
                    echo "$VAR_NAME=\"\${${TEMP_VAR_NAME}%?}\""
                fi
                echo "unset $TEMP_VAR_NAME"
            fi
        }
        function add_argsetter() {
            local ARG_NAME="$1"
            local ARG_TYPE="$2"
            local VAR_NAME="$3"
            local ARG_VALUE="$4"
            local ARG_CONTEXT="$5"
            if [[ $(contains "$ARG_TYPE" TYPE_PASSTHRU) ]]; then
                if [[ "${#ARG_NAME}" == '1' ]]; then
                    ARG_PASSTHRU+=("-$ARG_NAME")
                    debug "    passthru: -$ARG_NAME"
                else
                    ARG_PASSTHRU+=("--$ARG_NAME")
                    debug "    passthru: --$ARG_NAME"
                fi
                if [[ "${#ARG_VALUE}" != '0' ]]; then
                    if [[ $(contains "$ARG_VALUE" "'") ]]; then # need to escape
                        ARG_PASSTHRU+=("\$$VAR_NAME")
                        ARG_PASSTHRU_VAR_NAMES+=("$VAR_NAME")
                        ARG_PASSTHRU_VALUE_SETTERS+=("$(safe_assign_op "$VAR_NAME" "$ARG_VALUE")")
                        debug "    passthru (escaped value): $ARG_VALUE"
                    else
                        ARG_PASSTHRU+=("$ARG_VALUE")
                        debug "    passthru: $ARG_VALUE"
                    fi
                fi
                local PASSTHRU_VARNAME=$(hashmap_get ARGPARSE_ARGDEF_VAR_ALIAS $VAR_NAME)
                if [[ -z "$PASSTHRU_VARNAME" ]]; then return 0; fi
                VAR_NAME="$PASSTHRU_VARNAME"
            fi
            local VAR_FREESET=
            if [[ $(contains "$VAR_NAME" "_FREESET") ]] || [[ $(contains "$VAR_NAME" "_freeset") ]]; then
                VAR_FREESET=true
            fi
            debug "    setter: '$ARG_NAME' $ARG_TYPE; var: '$VAR_NAME' value: '$ARG_VALUE'"
            if [[ $(contains "$ARG_TYPE" FLAG) ]]; then
                debug "    set_flag: '$ARG_NAME' assigning to '\$$VAR_NAME' = 'true'"
                if [[ -n "$VAR_FREESET" ]]; then
                    ARG_SETTERS+=("$(safe_assign_op "$VAR_NAME" true)")
                else
                    if [[ $(contains "$VAR_ARRAY_INFO" "::${VAR_NAME}_VALUE_ONCE=$VAR_NAME::") ]]; then
                        error "flag '$ARG_NAME' cannot set" \
                                "this multiple times (while handling '$ARG_CONTEXT')"
                    fi
                    VAR_ARRAY_INFO="${VAR_ARRAY_INFO}::${VAR_NAME}_VALUE_ONCE=$VAR_NAME::"
                    ARG_SETTERS+=("$(safe_assign_op "$VAR_NAME" true)")
                fi
            else 
                local VAR_IS_ARRAY=
                local VAR_IS_UNIQUE_ARRAY=
                if [[ $(contains "$VAR_NAME" "_ARRAY") ]] || [[ $(contains "$VAR_NAME" "_array") ]]; then
                    VAR_IS_ARRAY=true
                fi
                if [[ $(contains "$VAR_NAME" "_UARRAY") ]] || [[ $(contains "$VAR_NAME" "_uarray") ]]; then
                    VAR_IS_ARRAY=true
                    VAR_IS_UNIQUE_ARRAY=true
                fi
                if [[ $VAR_IS_ARRAY ]] && [[ ! $(contains "$VAR_ARRAY_INFO" "::${VAR_NAME}_INIT::") ]]; then
                    VAR_ARRAY_INFO="${VAR_ARRAY_INFO}::${VAR_NAME}_INIT::"
                    ARG_SETTERS+=("")
                    ARG_SETTERS+=("# initializing [${YELLOW} $VAR_NAME ${NC}]")
                    ARG_SETTERS+=("$VAR_NAME=()")
                    debug "    set_param: '$ARG_NAME' assigning to '\$$VAR_NAME' (array) initialize"
                fi
                if [[ $VAR_IS_ARRAY ]]; then
                    debug "    set_param: '$ARG_NAME' assigning to '\$$VAR_NAME' (array) << '$ARG_VALUE'"
                    if [[ $VAR_IS_UNIQUE_ARRAY ]]; then
                        if [[ ! $(contains "$VAR_ARRAY_INFO" "::${VAR_NAME}_VALUE=(UNIQUE__$ARG_VALUE)::") ]]; then
                            VAR_ARRAY_INFO="${VAR_ARRAY_INFO}::${VAR_NAME}_VALUE=(UNIQUE__$ARG_VALUE)::"
                            ARG_SETTERS+=("$(safe_assign_op "$VAR_NAME" "$ARG_VALUE" true)")
                        else
                            debug "    set_param: '$ARG_NAME' assigning to '\$$VAR_NAME' "\
                                "(array) << '$ARG_VALUE' (denied; value already exists)"
                        fi
                    else
                        ARG_SETTERS+=("$(safe_assign_op "$VAR_NAME" "$ARG_VALUE" true)")
                    fi
                else
                    debug "    set_param: '$ARG_NAME' assigning to '\$$VAR_NAME' = '$ARG_VALUE'"
                    if [[ -n "$VAR_FREESET" ]]; then
                        ARG_SETTERS+=("$(safe_assign_op "$VAR_NAME" "$ARG_VALUE")")
                    else
                        if [[ $(contains "$VAR_ARRAY_INFO" "::${VAR_NAME}_VALUE_ONCE=$VAR_NAME::") ]]; then
                            error "param '$ARG_NAME' cannot set" \
                                "this multiple times (while handling '$ARG_CONTEXT')"
                        fi
                        VAR_ARRAY_INFO="${VAR_ARRAY_INFO}::${VAR_NAME}_VALUE_ONCE=$VAR_NAME::"
                        ARG_SETTERS+=("$(safe_assign_op "$VAR_NAME" "$ARG_VALUE")")
                    fi
                fi
            fi
        }
        local ARGS_ORIGINAL=("$@")
        local PRGM_NAME="$1"
        if [[ "${PRGM_NAME:0:5}" == 'name:' ]]; then
            PRGM_NAME="${PRGM_NAME:5}"
            shift
        else
            PRGM_NAME="arginfo"
        fi
        local DEBUG="$1"
        if [[ "$DEBUG" == "debug:false" ]]; then
            DEBUG=
            shift
        else
            DEBUG=true
        fi
        debug ""
        debug "name: $PRGM_NAME"
        for ARG_DEF in "${ARG_DEFS[@]}"; do
            local ARG_DEV_PRETTY=
            local ARGPARSE_ARG_KV=
            str_split "$ARG_DEF" --delim '; ' --into ARGPARSE_ARG_KV

            local PARAM_TYPE="${ARGPARSE_ARG_KV[0]}"

            local VAR_NAME="${ARGPARSE_ARG_KV[2]}"
            local VAR_NAME_ORIGINAL="$VAR_NAME"
            if [[ $(contains "$PARAM_TYPE" PASSTHRU) ]]; then
                local VAR_NAME_UID="$(openssl rand -base64 24)"
                VAR_NAME_UID="${VAR_NAME_UID//+/z}"
                VAR_NAME_UID="${VAR_NAME_UID////z}"
                VAR_NAME="TMP_PASSTHRU_VAR_$VAR_NAME_UID"
                local "ARGPARSE_ARGDEF_VAR_ALIAS_$VAR_NAME=${VAR_NAME_ORIGINAL}"
            fi
            local PARAM_SPECS="${ARGPARSE_ARG_KV[3]}"
            local "ARGPARSE_ARGDEF_TYPE_${VAR_NAME}=TYPE_${PARAM_TYPE}"
            local "ARGPARSE_ARGDEF_SPEC_${VAR_NAME}=$PARAM_SPECS"

            # must be done after VAR_NAME resolution
            local VAR_ARG_DEF="${ARGPARSE_ARG_KV[1]}"
            local ARGPARSE_VAR_ARG_DEF_SPLIT=
            str_split "$VAR_ARG_DEF" --delim ',' --into ARGPARSE_VAR_ARG_DEF_SPLIT
            local ARG_ALIAS=
            if [[ "${#ARGPARSE_VAR_ARG_DEF_SPLIT[@]}" == '0' ]]; then
                error "received no flag or longhand param definition" \
                    "(while handling '$PARAM_TYPE ${ARGPARSE_ARG_KV[1]} ${ARGPARSE_ARG_KV[2]}')"
            fi
            for ARG_ALIAS in "${ARGPARSE_VAR_ARG_DEF_SPLIT[@]}"; do
                local ARG_ALIAS_ORI="$ARG_ALIAS"
                if [[ "${ARG_ALIAS:0:1}" == "-" ]]; then ARG_ALIAS="${ARG_ALIAS:1}"; fi
                if [[ "${ARG_ALIAS:0:1}" == "-" ]]; then ARG_ALIAS="${ARG_ALIAS:1}"; fi
                if [[ "${ARG_ALIAS_ORI:0:2}" == '--' ]] && [[ "${#ARG_ALIAS}" == '1' ]]; then
                    error "single-letter longhand parameter such as '$ARG_ALIAS_ORI' is not allowed" \
                        "(while handling '$PARAM_TYPE ${ARGPARSE_ARG_KV[1]}" \
                        "${ARGPARSE_ARG_KV[2]}')" 
                fi
                local ARG_ALIAS_TRIMMED="${ARG_ALIAS//-/_}"
                if [[ "$(hashmap_get ARGPARSE_ARGDEF_NAME $ARG_ALIAS_TRIMMED)" ]]; then
                    error "parameter '$ARG_ALIAS_ORI' is already registered" \
                        "(while handling '$PARAM_TYPE ${ARGPARSE_ARG_KV[1]}" \
                        "${ARGPARSE_ARG_KV[2]}')" 
                fi
                local "ARGPARSE_ARGDEF_NAME_${ARG_ALIAS_TRIMMED}=${VAR_NAME}"
            done
            
            local PARAM_DEF_DEBUG="$(echo -e "$PARAM_TYPE: [${YELLOW} $VAR_NAME ${NC}]${CYAN}" \
                                    "${ARGPARSE_ARG_KV[1]} ${NC}$PARAM_SPECS")"
            local VAR_DEFAULT="${ARGPARSE_ARG_KV[4]}"
            if [[ "$VAR_DEFAULT" != '__ARGPARSE_PARAM_DEFAULT_DEFAULT__' ]]; then
                local DEFAULT_VAL_START_AT="$(strindex "$ARG_DEF" '; default:')"
                (( DEFAULT_VAL_START_AT=DEFAULT_VAL_START_AT+10 ))
                VAR_DEFAULT="${ARG_DEF:$DEFAULT_VAL_START_AT}"
                debug "$PARAM_DEF_DEBUG default: $VAR_DEFAULT"
                ARG_SETTERS+=("$(safe_assign_op "$VAR_NAME_ORIGINAL" "$VAR_DEFAULT")")
            else
                debug "$PARAM_DEF_DEBUG"
            fi
        done
        debug ""
        local ARG=
        local REMAINING_ARGS=()
        local LAST_ARG=
        local LAST_ARG_NAME=
        local LAST_ARG_TYPE=
        local LAST_ARG_VAR_NAME=
        local SHOULD_PASSOVER=
        SHIFT_COUNT=0
        for ARG in "$@"; do
            local ARG_CONTEXT="$LAST_ARG $ARG"
            LAST_ARG="$ARG"
            if [[ "$SHOULD_PASSOVER" == true ]]; then
                debug "passover:${CYAN}  '$ARG'  ${NC}"
                REMAINING_ARGS+=("$ARG")
                continue
            fi
            (( SHIFT_COUNT=SHIFT_COUNT+1 ))
            if [[ -n "$LAST_ARG_NAME" ]] && [[ "${ARG:0:1}" == "-" ]]; then
                if [[ "$LAST_ARG_TYPE" == 'TYPE_HYBRID' ]] || [[ $(contains "$LAST_ARG_TYPE" PASSTHRU) ]]; then
                    add_argsetter "$LAST_ARG_NAME" "$LAST_ARG_TYPE" "$LAST_ARG_VAR_NAME" '' "$ARG_CONTEXT"
                    LAST_ARG_NAME=
                    LAST_ARG_TYPE=
                    LAST_ARG_VAR_NAME=
                else
                    error "param '$LAST_ARG_NAME' requires a value ," \
                        "but instead got '$ARG' (while handling '$ARG_CONTEXT')"
                fi
            fi
            debug "processing:${CYAN}  '$ARG' ${NC}"
            if [[ "${ARG:0:2}" == "--" ]] && [[ "$ARG" != "--" ]]; then
                local ARG_NAME=
                local ARG_VALUE=
                local HAS_VALUE=
                local EQ_POS=$(strindex "$ARG" '=')
                if (( EQ_POS > 0 )); then
                    ARG_NAME="${ARG:0:$EQ_POS}"
                    ARG_NAME="${ARG_NAME:2}"
                    ARG_VALUE="${ARG:((EQ_POS+1))}"
                    HAS_VALUE=true
                else
                    ARG_NAME="${ARG:2}"
                fi
                local ARG_NAME_TRIMMED="${ARG_NAME//-/_}"
                local VAR_NAME=$(hashmap_get ARGPARSE_ARGDEF_NAME $ARG_NAME_TRIMMED)
                if [[ -n "$VAR_NAME" ]]; then
                    local ARG_TYPE=$(hashmap_get ARGPARSE_ARGDEF_TYPE $VAR_NAME)
                    if [[ -n "$HAS_VALUE" ]]; then
                        add_argsetter "$ARG_NAME" $ARG_TYPE "$VAR_NAME" "$ARG_VALUE" "$ARG_CONTEXT"
                    else
                        LAST_ARG_NAME="$ARG_NAME"
                        LAST_ARG_TYPE="$ARG_TYPE"
                        LAST_ARG_VAR_NAME="$VAR_NAME"
                    fi
                    continue
                fi
            elif [[ "${ARG:0:1}" == "-" ]] && [[ "$ARG" != "-" ]]; then
                local IDEN="${ARG:1}"
                for (( i=0; i < ${#IDEN}; i++ )); do
                    local FLAG_CHAR="${IDEN:$i:1}"
                    local VAR_NAME=$(hashmap_get ARGPARSE_ARGDEF_NAME $FLAG_CHAR)
                    if [[ $VAR_NAME ]]; then
                        local ARG_TYPE=$(hashmap_get ARGPARSE_ARGDEF_TYPE $VAR_NAME)
                        if [[ $(contains "$ARG_TYPE" FLAG) ]]; then
                            add_argsetter "$FLAG_CHAR" "$ARG_TYPE" "$VAR_NAME" '' "$ARG_CONTEXT"
                        else
                            local ARG_VALUE="${IDEN:(($i+1))}"
                            if [[ -z "$ARG_VALUE" ]]; then
                                LAST_ARG_NAME="$FLAG_CHAR"
                                LAST_ARG_TYPE="$ARG_TYPE"
                                LAST_ARG_VAR_NAME="$VAR_NAME"
                                break
                            fi
                            add_argsetter "$FLAG_CHAR" "$ARG_TYPE" "$VAR_NAME" "$ARG_VALUE" "$ARG_CONTEXT"
                            break
                        fi
                    else
                        error "unknown short parameter name '$FLAG_CHAR'" \
                            " (while handling '$ARG_CONTEXT')"
                    fi
                done
                continue
            fi
            if [[ -n "$LAST_ARG_NAME" ]]; then
                local ARG_VALUE="$ARG"
                if [[ $(contains "$LAST_ARG_TYPE" FLAG) ]]; then
                    add_argsetter "$LAST_ARG_NAME" "$LAST_ARG_TYPE" "$LAST_ARG_VAR_NAME" '' "$ARG_CONTEXT"
                    LAST_ARG_NAME=
                    LAST_ARG_TYPE=
                    LAST_ARG_VAR_NAME=
                else 
                    add_argsetter "$LAST_ARG_NAME" "$LAST_ARG_TYPE" "$LAST_ARG_VAR_NAME" "$ARG_VALUE" "$ARG_CONTEXT"
                    LAST_ARG_NAME=
                    LAST_ARG_TYPE=
                    LAST_ARG_VAR_NAME=
                    continue
                fi
            elif [[ "${ARG:0:1}" == "-" ]]; then
                error "unknown parameter '$ARG'"
            fi
            debug "passover: reached passover argument section passing over the remaining args."
            debug ""
            SHOULD_PASSOVER=true
            debug "passover:${CYAN}  '$ARG'  ${NC}"
            REMAINING_ARGS+=("$ARG")
        done
        debug ""
        output ""
        output "function $SAFE_ASSIGN(){ IFS='' read -r -d '' \"\${1}\" || true; }"
        output "ARG_PARSED=true"
        output "unset ARG_DEFS"
        output ""
        for ARG_PASSTHRU_VALUE_SETTER in "${ARG_PASSTHRU_VALUE_SETTERS[@]}"; do
            output "$ARG_PASSTHRU_VALUE_SETTER"
        done
        output "ARG_PASSTHRU=("
        local PASSTHRU_VARNAMES="${ARG_PASSTHRU_VAR_NAMES[@]}"
        for PASSTHRU_ARG in "${ARG_PASSTHRU[@]}"; do
            if [[ "${PASSTHRU_ARG:0:1}" == '$' ]] && \
                [[ $(contains "$PASSTHRU_VARNAMES" "${PASSTHRU_ARG:1}") ]]; then
                output "\"${PASSTHRU_ARG}\""
            else
                output "'$PASSTHRU_ARG'"
            fi
        done
        output ")"
        for ARG_PASSTHRU_VAR_NAME in "${ARG_PASSTHRU_VAR_NAMES[@]}"; do
            output "unset $ARG_PASSTHRU_VAR_NAME"
        done
        output ""
        local SETTER=
        for SETTER in "${ARG_SETTERS[@]}"; do
            output "$SETTER"
        done
        (( SHIFT_COUNT=SHIFT_COUNT-1 ))
        output ""
        if [[ "$SHIFT_COUNT" -gt 0 ]]; then
            output "# shifting by $SHIFT_COUNT"
            output "shift $SHIFT_COUNT"
        fi
    }
    if [[ "$ACTION" == "parse" ]]; then 
        parse "$@";
        ARG_DEFS=()
        return 0
    fi
    error "Unknown argp action '$ACTION' supported actions are" \
        "[ parse, flag, param, hybrid, passthru, passthru_flag ]"
}

BASHLIB_IMPORTS="$BASHLIB_IMPORTS:argp:"
