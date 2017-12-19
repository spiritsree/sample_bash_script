function prog_sample() {
    source spinner.sh
    sleep $1 &
    spinner $!
}
