#!/usr/bin/env bash

###################################################################
# Script Name   : colors.sh
# Description   : Manage color palette when printing to terminal
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

declare -A __COLORS_CLASSIC_ESCAPE_CHAR=([BASH]="\e" [OCT]="\033" [HEX]="\x1b")
declare -A __COLORS_CLASSIC_REF=([BLACK]=30 [RED]=31 [GREEN]=32 [YELLOW]=33 [BLUE]=34 [PURPLE]=35 [CYAN]=36 [WHITE]=37)
declare -A __COLORS_CLASSIC_STYLES_REF=([NORMAL]=0 [BOLD]=1 [LOW_INTENSITY]=2 [UNDERLINE]=4 [BLINK]=5 [REVERSE]=7 [INVISIBLE]=8)

declare -A __COLORS_TPUT_REF=([BLACK]=0 [RED]=124 [GREEN]=64 [YELLOW]=136 [BLUE]=33 [PURPLE]=125 [CYAN]=37 [WHITE]=15)
declare -A __COLORS_TPUT_STYLES_REF=([NORMAL]="sgr0" [BOLD]="bold" [LOW_INTENSITY]="dim" [UNDERLINE]="smul" [BLINK]="blink" [REVERSE]="smso")

function __color_tput() {
    local message="${1}"
    local styles="${2}"
    local style=""

    IFS=', ' read -r -a styles_arr <<<"$styles"
    for style_str in "${styles_arr[@]}"; do
        style_str=${style_str^^}

        if [[ $style_str == BG-* ]]; then
            style_str=${style_str:3}

            # TODO
            if [[ $style_str == HI-* ]]; then
                style_str=${style_str:3}
            fi
            if [[ ! ${__COLORS_TPUT_REF[${style_str}]-abc} = "abc" ]]; then
                local background_idx=$((${__COLORS_TPUT_REF[$style_str]}))
            fi
        fi

        if [[ ! ${__COLORS_TPUT_STYLES_REF[$style_str]-abc} = "abc" ]]; then
            style="${__COLORS_TPUT_STYLES_REF[$style_str]}"
        fi

        if [[ $style_str == FG-* ]]; then
            style_str=${style_str:3}
            # TODO
            if [[ $style_str == HI-* ]]; then
                style_str=${style_str:3}
            fi
            if [[ ! ${__COLORS_TPUT_REF[${style_str}]-abc} = "abc" ]]; then
                local foreground_idx=$((${__COLORS_TPUT_REF[$style_str]}))
            fi
        fi
    done

    if [[ -z ${foreground_idx} && -z ${background_idx} ]] && [[ ${style} = "0" ]]; then
        echo "${message}"
        return
    fi

    local start=""
    if [[ ! -z ${style} ]]; then
        start="${start}$(tput ${style})"
    fi

    if [[ ! -z ${background_idx} ]]; then
        start="${start}$(tput setab ${background_idx})"
    fi
    if [[ ! -z ${foreground_idx} ]]; then
        start="${start}$(tput setaf ${foreground_idx})"
    fi

    echo "${start}${message}$(tput sgr0)"
}

function __color_classic() {
    local message="${1}"
    local styles="${2}"
    local escape_char=${3:-${__COLORS_CLASSIC_ESCAPE_CHAR[BASH]}}
    local background_idx=""
    local foreground_idx=""
    local style="0"
    local hi=0

    IFS=', ' read -r -a styles_arr <<<"$styles"
    for style_str in "${styles_arr[@]}"; do
        hi=0
        style_str=${style_str^^}

        if [[ ! ${__COLORS_CLASSIC_ESCAPE_CHAR[$style_str]-abc} = "abc" ]]; then
            escape_char="${__COLORS_CLASSIC_ESCAPE_CHAR[$style_str]}"
        fi

        if [[ $style_str == BG-* ]]; then
            style_str=${style_str:3}

            if [[ $style_str == HI-* ]]; then
                style_str=${style_str:3}
                hi=60
            fi
            if [[ ! ${__COLORS_CLASSIC_REF[${style_str}]-abc} = "abc" ]]; then
                local background_idx=$((${__COLORS_CLASSIC_REF[$style_str]} + 10))
                background_idx=$((${background_idx} + $hi))
            fi
        fi

        if [[ ! ${__COLORS_CLASSIC_STYLES_REF[$style_str]-abc} = "abc" ]]; then
            style="${__COLORS_CLASSIC_STYLES_REF[$style_str]}"
        fi

        if [[ $style_str == FG-* ]]; then
            style_str=${style_str:3}
            if [[ $style_str == HI-* ]]; then
                style_str=${style_str:3}
                hi=60
            fi
            if [[ ! ${__COLORS_CLASSIC_REF[${style_str}]-abc} = "abc" ]]; then
                local foreground_idx=$((${__COLORS_CLASSIC_REF[$style_str]}))
                foreground_idx=$((${foreground_idx} + $hi))
            fi
        fi
    done

    if [[ -z ${foreground_idx} && -z ${background_idx} ]] && [[ ${style} = "0" ]]; then
        echo "${message}"
        return
    fi

    local start="${escape_char}["
    if [[ ! -z ${style} ]]; then
        start="${start}${style}"
    fi

    if [[ ! -z ${foreground_idx} ]]; then
        start="${start};${foreground_idx}"
    fi

    if [[ ! -z ${background_idx} ]]; then
        start="${start};${background_idx}"

    fi

    start="${start}m"
    echo "$(echo -en ${start})${message}$(echo -en ${escape_char}[m)"
}

function color() {
    local message="${1}"
    local styles="${2}"
    local force_classic=false
    local classic_escape_char=""

    IFS=', ' read -r -a styles_arr <<<"$styles"
    for style_str in "${styles_arr[@]}"; do
        local style="${style_str^^}"
        style=${style:2}
        if [[ ! "${__COLORS_CLASSIC_ESCAPE_CHAR[${style}]}-abc" = "-abc" ]]; then
            force_classic=true
            classic_escape_char="${__COLORS_CLASSIC_ESCAPE_CHAR[${style_str^^}]}"
        fi
    done

    if [ -x /usr/bin/tput ] && tput setaf 1 &>/dev/null; then
        if [ ${force_classic} = false ]; then
            echo "$(__color_tput "${message}" "${styles}")"
            return
        fi
    fi

    echo $(__color_classic "${message}" "${styles}" "${classic_escape_char}")
}
