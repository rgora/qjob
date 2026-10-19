# Normalize options for the existing dispatcher. Bash 3.2+; no GNU getopt needed.
# Stops at the first positional argument, as the former getopt '+' mode did.
qjob_parse_options() {
    local short_spec=${1#+} long_spec=$2 opt word value takes_value
    shift 2
    local -a result=()
    while (( $# )); do
        case $1 in
            --) shift; break ;;
            --*)
                word=${1#--}
                opt=${word%%=*}
                takes_value=0
                case ",$long_spec," in
                    *",$opt:,"*) takes_value=1 ;;
                    *",$opt,"*) ;;
                    *) printf '%s: unknown option --%s\n' "$QJOB_CMD" "$opt" >&2; return 2 ;;
                esac
                if (( takes_value )); then
                    if [[ $word == *=* ]]; then value=${word#*=}; else
                        (( $# >= 2 )) || { printf '%s: --%s needs a value\n' "$QJOB_CMD" "$opt" >&2; return 2; }
                        shift; value=$1
                    fi
                    result+=("--$opt" "$value")
                else
                    [[ $word != *=* ]] || { printf '%s: --%s does not take a value\n' "$QJOB_CMD" "$opt" >&2; return 2; }
                    result+=("--$opt")
                fi
                shift ;;
            -?*)
                word=${1#-}; shift
                while [ -n "$word" ]; do
                    opt=${word:0:1}; word=${word:1}
                    [[ $opt != : && $short_spec == *"$opt"* ]] \
                        || { printf '%s: unknown option -%s\n' "$QJOB_CMD" "$opt" >&2; return 2; }
                    if [[ $short_spec == *"$opt:"* ]]; then
                        if [ -n "$word" ]; then value=$word; word=''; else
                            (( $# )) || { printf '%s: -%s needs a value\n' "$QJOB_CMD" "$opt" >&2; return 2; }
                            value=$1; shift
                        fi
                        result+=("-$opt" "$value")
                    else
                        result+=("-$opt")
                    fi
                done ;;
            *) break ;;
        esac
    done
    result+=(-- "$@")
    printf '%q ' "${result[@]}"
}
