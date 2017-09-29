function prog_sample() {
    source spinner.sh
    sleep 10 &
    spinner $!
}
