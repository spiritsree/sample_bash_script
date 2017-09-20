function file_tests() {
    _file=$1

    [ ! -r "${_file}" ] && { echo "File ${_file} doesn't exist or not readable."; critical "File ${_file} doesn't exist or not readable."; return 1; }
    [ ! -s "${_file}" ] && { echo "File ${_file} is empty."; critical "File  ${_file} is empty."; return 1; }
    return 0
}

function file_exec() {
    _file=$1
    [ ! -x "${_file}" ] && { echo "File ${_file} not executable."; critical "File ${_file} not executable."; return 1; }
    return 0
}
