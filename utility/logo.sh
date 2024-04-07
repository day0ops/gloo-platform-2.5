#!/usr/bin/env bash

###################################################################
# Script Name   : logo.sh
# Description   : Print logo
# Author        : Kasun Talwatta
# Email         : kasun.talwatta@solo.io
# Version       : v0.1
###################################################################

UTILITY_DIR=$(realpath "$(dirname "${BASH_SOURCE[0]}")")
source $UTILITY_DIR/colors.sh

function print_logo() {
    local centered_header
    local color_code=$1
    local message=$2

    total_length=60
    fill=" "
    header_fill=$(( ( $total_length / 2 ) - ( ${#message} / 2 ) ))
    for (( i=0; i<$header_fill; i++ )); do
        centered_header="${centered_header}${fill}"
    done

    echo -e "$(color "\n==================================================================" ${color_code})"
    echo "$(color "        ******                                              " ${color_code})"
    echo "$(color "      ****-..:+*                                            " ${color_code})"
    echo "$(color "     *****-. .=**                                           " ${color_code})"
    echo "$(color "     **************    ******++++++****                     " ${color_code})"
    echo "$(color "     *****************+++++++=-:::::-=++***                 " ${color_code})"
    echo "$(color "       ********  **+++++++++:...........:=+**               " ${color_code})"
    echo "$(color "               ***+++++++++++===++++++=:...-+**             " ${color_code})"
    echo "$(color "             ***++++++++++++++++++++++++++-..=**            " ${color_code})"
    echo "$(color "             **+++++++++++++++++++++++++++++-:=**           " ${color_code})"
    echo "$(color "            ***++++++++++++++++++++++++++++++=:+**          " ${color_code})"
    echo "$(color "           ***++++++*%%*++++++++++++++*%%#*+++++**          " ${color_code})"
    echo "$(color "        ******+++++#%%*-**+++++++++++*%%%+**+++++****       " ${color_code})"
    echo "$(color "     **+-+****+++++#%%%%%*+++++++++++*%%%%%*+++++**--+**    " ${color_code})"
    echo "$(color "   **-.+*******++++++*#*+++++++++++++++***+++++++***=..+**  " ${color_code})"
    echo "$(color " **+.-+********+++++++++++##----:::*%*+++++++++++****+:.-** " ${color_code})"
    echo "$(color " *+-=*****  ****++++++++++*%%%####%%#+++++++++++** ****++***" ${color_code})"
    echo "$(color " *+-****    *****+++++++++++*##*##*++++++++++++***  ********" ${color_code})"
    echo "$(color "  ****      *******+++++++++++++++++++++++++++***     ****  " ${color_code})"
    echo "$(color "            *********++++++++++++++++++++++******           " ${color_code})"
    echo "$(color "             ************+++++++++++++++********            " ${color_code})"
    echo "$(color "              *********************************             " ${color_code})"
    echo "$(color "               ********************************             " ${color_code})"
    echo "$(color "                ******************************              " ${color_code})"
    echo "$(color "               %%#***********###************%%              " ${color_code})"
    echo "$(color "              %%%%%%******%%%%%%%%%#*****#%%%%%             " ${color_code})"
    echo "$(color "                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%              " ${color_code})"
    echo "$(color "                     %%%%%%%%%%%%%%%%%%%                    " ${color_code})"
    echo -e "$(color "\n\n${centered_header}${2}${centered_header}" ${color_code})"
    echo -e "$(color "==================================================================\n" ${color_code})"
}
