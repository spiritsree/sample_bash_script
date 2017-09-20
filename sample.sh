#!/usr/bin/env bash

### Configuration
#####################################################################

# Environment variables and their defaults
arg_help=0
arg_debug=0
arg_dryrun=0
arg_test=0
arg_sample=0
arg_pid=$$
arg_conf=0
LOG_FILE='/var/log/sample.log'
HOST_ID=`/bin/hostname`
LOCK_FILE='/var/run/sample.lock'


### Options
#####################################################################

# Command-line options.
read -r -d '' usage <<-'EOF'
OPTIONS:
  -d                        Enables debug mode
  -h                        Help
  -n                        Dry Run
  -c <conf_file_path>       Configuration File
  --test_option             This is a test option
  --sample_option[=value]   This is a sample option
EOF


### Functions
#####################################################################

# Function for color formatting the log lines.
function _fmt() {
    local color_ok="\x1b[32m"
    local color_bad="\x1b[31m"
    local color="${color_bad}"
    if [ "${1}" = "debug" ] || [ "${1}" = "info" ]; then
        color="${color_ok}"
    fi

    local color_reset="\x1b[0m"
    if [[ "${TERM}" != "xterm"* ]] || [ -t 1 ]; then
        # Don't use colors on pipes or non-recognized terminals
        color=""; color_reset=""
    fi
    if [[ -z ${CLUSTER:-} ]]; then
        echo -e "$(date +"%Y-%m-%d %H:%M:%S %Z") ${color}$(printf "[%9s]" ${1}) [ PID=${arg_pid}][ GENERAL]${color_reset}";
    else
        echo -e "$(date +"%Y-%m-%d %H:%M:%S %Z") ${color}$(printf "[%9s]" ${1}) [ PID=${arg_pid}][ $( echo ${CLUSTER} | tr [a-z] [A-Z])]${color_reset}";
    fi
}

# Functions for logging.
function critical() { echo "$(_fmt critical) ${@}" >> ${LOG_FILE} || true; }
function info() { echo "$(_fmt info) ${@}" >> ${LOG_FILE} || true; }
function debug() { echo "$(_fmt debug) ${@}" >> ${LOG_FILE} || true; }

# Function to display help.
function help() {
    echo "" 1>&2
    local emsg="$@"
    local padlength=$((${#emsg} + 6))
    local pad=$(printf '%0.s#' $(seq 1 ${padlength}))
    printf '\e[1;31m%*s\n' "$padlength" "$pad" 1>&2
    printf "#  %*s  #\n" $((${#emsg})) "$emsg" 1>&2
    printf '%*.*s\e[0m\n' 0 "$padlength" "$pad" 1>&2
    echo "" 1>&2
    echo ""Usage: ${0} [OPTIONS]"" 1>&2
    echo "" 1>&2
    echo "  ${usage}" 1>&2
    echo "" 1>&2
}

# Function to time the end of prog.
function _progend() {
    ENDTIME=`date +%s%N | cut -b1-13`
    TIMETAKEN=`expr ${ENDTIME} - ${STARTTIME}`
    info "Sample completed in ${TIMETAKEN} milliseconds."
}

# Function to cleanup on exit.
function cleanup_before_exit() {
    unlink ${TMP_FILE}
    unlink ${LOCK_FILE}
    _progend
}

# Function for sample prog.
function _sample() {
    source _sample.sh
    prog_sample
}

# Function for test prog.
function _test() {
    source _test.sh
    prog_test
}

### Parse command-line options
#####################################################################

# Help if no options.
if [[ -z $@ ]]; then
    help "Sample Help"
    exit 1
elif [[ ! $@ =~ ^- ]];then
    help "$0: Error - Unrecognized option"
    exit 1
fi

argv=( $@ )

OPTION=`getopt -o dhnc: --long test_option,sample_option:: -n "$0" -- "${argv[@]}" 2> /dev/null`
if [ $? -ne 0 ];then
    help "$0: Error - Unrecognized option"
    exit 1
fi
eval set -- "${OPTION}"

[[ `echo ${OPTION} | grep -o 'option' | wc -l` > 1 ]] && { help "$0: Use any one option at a time."; exit 1; }

# extract options and their arguments into variables.
while true ; do
    case "$1" in
        -d) # enable debug
            arg_debug=1
            shift;;
        -h) # show help
            arg_help=1
            shift ;;
        -n)
            arg_dryrun=1
            shift ;;
        --test_option)
            arg_test=1
            shift ;;
        --sample_option)
            arg_sample=1
            [[ -n $2 ]] && sample_value=$2
            shift 2 ;;
        -c)
            CONF_FILE=$2
            [[ -z ${CONF_FILE} ]] && { help "$0: Provide a valid config file."; exit 1; }
            [[ "${CONF_FILE}" =~ ^- ]] && { help "$0: Provide config file"; exit 1; }
            arg_conf=1
            shift 2 ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; critical 'Internal error! Get options failed.'; exit 1 ;;
    esac
done

[[ ${arg_test} -eq 1 ]] && [[ ${arg_sample} -eq 1 ]] && { help "$0: test and sample cannot be used together."; exit 1; }

# help mode
if [ "${arg_help}" = "1" ]; then
    # Help exists with code 1
    help 'Sample Help'
    exit 0
fi

# debug mode
if [ "${arg_debug}" = "1" ]; then
    set -o xtrace
fi


### Runtime
#####################################################################

_main() {
    STARTTIME=`date +%s%N | cut -b1-13`
    TMP_FILE=`mktemp /tmp/sample_temp.XXXXXXXXXX`
    info "Sample started at ${STARTTIME} milliseconds"
    # Exit on error. Append ||true if you expect an error.
    set -o errexit
    set -o nounset

    # Bash will remember & return the highest exit code in a chain of pipes.
    set -o pipefail

    trap cleanup_on_trap INT TERM EXIT

    if [[ -e ${LOCK_FILE} ]]; then
       running_pid=`cat ${LOCK_FILE}`
       critical "Process already running with PID ${running_pid}"
       exit 1
    else
       echo "${arg_pid}" > ${LOCK_FILE}
    fi
    
    if [[ ${arg_conf} -eq 1 ]]; then
        source file_tests.sh
        if ! file_tests ${CONF_FILE}; then
    	    critical "Sample Config File ${CONF_FILE} doesn't exist or not readable."
            exit 1
        fi

        # conf file validation.
        while read line; do
            if [[ $line =~ ^$ ]]; then
                continue
            elif [[ $line =~ ^# ]]; then
                continue
            elif [[ $line =~ ^[A-Z_]+=$ || $line =~ ^[A-Z_]+=[^[:space:]#] ]]; then
                continue
            else
                critical "Check the validity of config file ${CONF_FILE}."
                critical "Suggestion: ${line} remove any special or space characters around = "
                exit 1
            fi
        done < ${CONF_FILE}
    
        # Load the config file to read the variables.
        source ${CONF_FILE}
    fi
    
    [[ ${arg_test} -eq 1 ]] && _test
    [[ ${arg_sample} -eq 1 ]] && _sample
    exit 0
}

_main

