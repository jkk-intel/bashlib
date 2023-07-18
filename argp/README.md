# argp

Argument parser written purely in bash with declarative syntax
(inspired by python argparse). Alternative to `getopt` and `getopts` which
has trouble handling long options (--long-option)

## Getting Started

```bash
# bash my_script.sh <PARAMETERS_SECTION...> <TRAILING_ARGUMENTS_SECTION...>
bash my_script.sh --file=test --started-at 1024 -e3000 -hn --debug-enabled trailing-params -p --example
```

```bash
# Declare your params
argp param -f --file FILE required
argp param -s --started-at STARTED_AT default:0
argp param -e --ended-at ENDED_AT default:0
argp flag -d --debug-enabled DEBUG_ENBLED
argp flag -c --cpu-enabled CPU_ENABLED
argp flag -h --host-enabled HOST_ENBLED
argp flag -n --network-enabled NET_ENABLED

# Parse & evaluate, start using the variables
eval "$(argp parse "$@")"

# if the script invocation was: 
# bash my_script.sh --file=test --started-at 1024 -e3000 \
#                   -hn --debug-enabled trailing-params -p --example
echo "$FILE"         # 'test'
echo "$STARTED_AT"   # '1024'
echo "$ENDED_AT"     # '3000'
echo "$CPU_ENABLED"  # '' => (never supplied; empty)
echo "$HOST_ENBLED"  # 'true'
echo "$NET_ENABLED"  # 'true'
echo "$DEBUG_ENBLED" # 'true'
echo "$@"            # 'trailing-params -p --example'
echo "$1"            # 'trailing-params'
echo "$2"            # '-p'
echo "$3"            # '--example'
```

## AUTHOR

@jkk-intel Joe K. Kim (joe.kim@intel.com) Intel Corporation

## LICENSE

MIT
