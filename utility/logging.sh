#!/usr/bin/env bash

###################################################################
# Script Name   : logging.sh
# Description   : Utility to manage logging
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/colors.sh

declare -A DEFAULT_LOGGER_STATE=([DEFAULT_LOG_LEVEL]=${LOG_LEVEL:-"WARNING"} [LOG_LEVEL]=${LOG_LEVEL:-"WARNING"} [DEFAULT_LOG_PREFIX]="1" [LOG_PREFIX]=${LOG_PREFIX:-"1"})
if [ -z "${LOGGER_STATE+x}" ]; then
    declare -A LOGGER_STATE
    for key in "${!DEFAULT_LOGGER_STATE[@]}"; do
        LOGGER_STATE[$key]=${DEFAULT_LOGGER_STATE[$key]}
    done
fi

declare -A LOG_COLORS=([5]="bg-red" [4]="fg-red" [3]="fg-yellow" [2]="fg-blue" [1]="fg-cyan" [0]="fg-white")
declare -A HEADER_TOTAL_LENGTH=100

function __split_by_delim() {
    a=()
    local car=""
    local cdr="$1"
    while
        car="${cdr%%"$2"*}"
        a+=("$car")
        cdr="${cdr:${#car}}"
        ((${#cdr}))
    do
        cdr="${cdr:${#2}}"
    done
    echo "${a[*]}"
}

function __resolve_log_level_subidx() {
    local level_name level_idx
    level_name="${1}"
    level_idx="${level_name: -1}"

    if [[ ${#level_name} == 1 || ! "$level_idx" =~ ^[0-9]+$ ]]; then
        level_idx="0"
    fi
    echo "${level_idx}"
}

function __resolve_log_level() {
    local level_name level_name_str level_idx log_level_subidx
    level_name="${1^^}"
    log_level_subidx="$(__resolve_log_level_subidx "${level_name}")"

    case "${level_name}" in
    SILENT | S | SILENT:* | S:* | 6:*)
        level_name_str="SILENT"
        level_idx="6"
        ;;
    CRITICAL | C | CRITICAL:* | C:* | 5:*)
        level_name_str="CRITICAL"
        level_idx="5"
        ;;
    ERROR | E | ERROR:* | E:* | 4:*)
        level_name_str="ERROR"
        level_idx="4"
        ;;
    WARNING | W | WARNING:* | W:* | 3:*)
        level_name_str="WARNING"
        level_idx="3"
        ;;
    INFO | I | INFO:* | I:* | 2:*)
        level_name_str="INFO"
        level_idx="2"
        ;;
    DEBUG | D | DEBUG:* | D:* | 1:*)
        level_name_str="DEBUG"
        level_idx="1"
        ;;
    *)
        level_name_str="VERBOSE"
        level_idx="0"
        ;;
    esac
    echo "${level_name_str} ${level_idx} ${log_level_subidx}"
}

function __reverse_arr() {
    local input_array reversed
    input_array=
    reversed=()
    local i
    for ((i = ${#input_array[@]}; i > 0; i--)); do
        reversed+=("${!i}")
    done
    echo
}

function __log_fn_trail() {
    local i functions_trail_array functions_trail_reversed functions_trail_reversed_str

    # load functions trail as a array
    IFS=' ' read -r -a functions_trail_array <<<${FUNCNAME[*]:2}

    # reverese array for readability
    functions_trail_reversed=()
    for i in "${functions_trail_array[@]}"; do
        functions_trail_reversed=(${i} "${functions_trail_reversed[@]}")
    done

    functions_trail_reversed_str="${functions_trail_reversed[*]}"
    functions_trail_reversed_str=${functions_trail_reversed_str//" "/">"}
    echo "${functions_trail_reversed_str}"
}

function _trim() {
    echo -e "${1}" | sed 's/^[ \t]*//;s/[ \t]*$//'
}

function __print_log_line() {
    local message="${1}"
    echo -en "\n${message}\n"
}

function __format_logger() {
    local log_level_idx message prefix
    local color_start color_end
    message=${1}
    log_level_idx=${2}
    log_level_subidx="${3}"
    prefix="${4}"
    header_char="${5}"
    predefined_color="${6}"

    local color="${predefined_color:-${LOG_COLORS[${log_level_idx}]}}"
    local colored=$(_trim "${prefix}\t${message}")
    case "${log_level_subidx}" in
    1)
        formatted=$(_trim "${prefix}\t# ${message}")
        colored=$(color "${formatted}" "${color}")
        ;;
    2)
        formatted=$(_trim "${prefix}\t## ${message}")
        colored=$(color "${formatted}" "${color}")
        ;;
    3)
        formatted=$(_trim "${prefix}\t### ${message}")
        colored=$(color "${formatted}" "${color}")
        ;;
    4)
        formatted=$(_trim "${prefix}\t#### ${message}")
        colored=$(color "${formatted}" "${color}")
        ;;
    5)
        formatted=$(_trim "${prefix}\t##### ${message}")
        colored=$(color "${formatted}" "${color}")
        ;;
    6)
        colored=""
        local message_array=($(__split_by_delim ${message} ","))
        for item in "${message_array[@]}"; do
            local item_str="$(echo -en $(color "\t-${prefix} ${item}\n" "${color}"))"
            colored="${colored} ${item_str}"
        done
        ;;
    7)
        colored=""
        local message_array=(${message})
        local i=1
        for item in "${message_array[@]}"; do
            local item_str="$(echo -en $(color "\t${i}.${prefix} ${item}\n" "${color}"))"
            colored="${colored} ${item_str}"
            i=$((i + 1))
        done
        ;;
    8)
        fill=$header_char
        colored=""
        total_length=$HEADER_TOTAL_LENGTH
        ftitle_border="\n"
        for ((i = 1; i <= $total_length; i++)); do
            ftitle_border=$ftitle_border$fill
        done
        ftitle_spacing="          "
        ftitle_fill=$((($total_length / 2) - (${#message} / 2) - ${#ftitle_spacing}))
        for ((i = 0; i < $ftitle_fill; i++)); do
            formatted_ftitle="${formatted_ftitle}${fill}"
        done
        formatted_ftitle="${formatted_ftitle}${ftitle_spacing}${message}${ftitle_spacing}${formatted_ftitle}"
        if ((${#message} % 2)); then
            formatted_ftitle="${formatted_ftitle::-1}"
        fi
        fmt_colored="$(echo -en "$(color "${ftitle_border}\n${formatted_ftitle}${ftitle_border}\n" "${color}")")"
        colored="${fmt_colored}"
        ;;
    *)
        formatted=$(_trim "${prefix}\t${message}")
        colored=$(color "${formatted}" "${color}")
        ;;
    esac
    __print_log_line "${colored}"
}

function logger() {
    local message
    local log_level_array log_level_str log_level_idx log_level_subidx
    local current_global_log_level_array current_global_log_level_idx # current_global_log_level_str
    local functions_trail log_date log_files_trail
    local prefix
    local predefined_color
    local header_char
    message=${2}

    if [[ $# == 4 ]]; then
        header_char=${3}
        predefined_color=${4}
    elif [[ $# == 3 ]]; then
        header_char=${3}
        if [[ ${#header_char} != 1 ]]; then
            predefined_color=${3}
            header_char=""
        fi
    fi

    if [[ ! ($header_char =~ ['!=-@#$%^&*_+']) ]]; then
        header_char=""
    fi

    # identify log level
    read -a log_level_array <<<"$(__resolve_log_level "${1}")"
    # echo "log: ${log_level_array[0]} & ${log_level_array[1]} & ${log_level_array[2]}"
    log_level_str=${log_level_array[0]}
    log_level_idx=${log_level_array[1]}
    log_level_subidx=${log_level_array[2]}

    # identify global log level
    read -a current_global_log_level_array <<<"$(__resolve_log_level "${LOGGER_STATE[LOG_LEVEL]}")"
    # echo "global: ${current_global_log_level_array[0]} & ${current_global_log_level_array[1]}"
    # current_global_log_level_str=${current_global_log_level_array[0]}
    current_global_log_level_idx=${current_global_log_level_array[1]}

    # function trail and files
    #functions_trail=$(__log_fn_trail)

    # current_script_file="${0##*/}"
    # log_script_file="${BASH_SOURCE##*/}"
    # if [[ $current_script_file == $log_script_file ]]; then
    #   log_files_trail=$current_script_file
    # else
    #   log_files_trail="$current_script_file>$log_script_file"
    # fi

    # log date
    log_date=$(date +"%Y-%m-%dT%H:%M:%S%:z")

    if [[ ! $current_global_log_level_idx > $log_level_idx ]]; then
        prefix=""
        if [[ ${LOGGER_STATE[LOG_PREFIX]} == "1" ]]; then
            prefix="${log_date}-[${log_level_str}]"
        fi
        __format_logger "${message}" "${log_level_idx}" "${log_level_subidx}" "${prefix}" "${header_char}" "${predefined_color}"
    fi
}

function logger_off {
    LOGGER_STATE[LOG_LEVEL]="SILENT"
}

function log_level {
    local log_level_str

    read -a log_level_array <<<"$(__resolve_log_level "${1}")"
    log_level_str=${log_level_array[0]}
    LOGGER_STATE[LOG_LEVEL]="$log_level_str"
}

function logger_on {
    LOGGER_STATE[LOG_LEVEL]=${LOGGER_STATE[DEFAULT_LOG_LEVEL]}
}

function log_prefix {
    LOGGER_STATE[LOG_PREFIX]="${1}"
}

function log_level_safe() {
    local func_log_level=${1}
    local func_log_prefix=${2}

    local origin_log_level="${LOGGER_STATE[LOG_LEVEL]}"
    if [[ ${origin_log_level} == ${LOGGER_STATE[DEFAULT_LOG_LEVEL]} ]]; then
        log_level "${func_log_level}"
    fi
    local origin_log_prefix="${LOGGER_STATE[LOG_PREFIX]}"
    if [[ ${origin_log_prefix} == ${LOGGER_STATE[DEFAULT_LOG_PREFIX]} ]]; then
        log_prefix ${func_log_prefix}
    fi

    echo "${origin_log_level} ${origin_log_prefix}"
}

function log_level_restore() {
    local func_log_level=${1}
    local func_log_prefix=${2}

    log_level "${func_log_level}"
    log_prefix ${func_log_prefix}
}
