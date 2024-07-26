#!/bin/bash
FILENAME=$1
LOGFILE="test_connectivity.log"
TIMEOUT_DURATION=1
DEFAULT_PROTOCOL='ICMP'
DEFAULT_ACCESS='ALLOW'
DEFAULT_SERVER='localhost'
DEFAULT_PORT='123'

# Function to check for required commands
check_commands() {
    local commands=("wget" "timeout" "ip" "sed" "hostname" "getent" "date")
    for cmd in "${commands[@]}"; do
        if ! command -v $cmd &> /dev/null; then
            echo -e "ERROR\t$cmd is not installed." | tee -a $LOGFILE
            exit 1
        fi
    done
}

# Function to identify arguments
identify_arguments() {
    local arg1=${1^^}
    local arg2=${2^^}
    local arg3=${3^^}
    local arg4=${4^^}

    local port="$DEFAULT_PORT"
    local protocol="$DEFAULT_PROTOCOL"
    local access_control="$DEFAULT_ACCESS"
    local server_name="$DEFAULT_SERVER"

    for arg in "$arg1" "$arg2" "$arg3" "$arg4"; do
        if [[ $arg =~ ^[0-9]+$ ]]; then
            port=$arg
        elif [[ $arg =~ ^(TCP|UDP|ICMP|HTTP|HTTPS)$ ]]; then
            protocol=$arg
        elif [[ $arg =~ ^(ALLOW|DENY)$ ]]; then
            access_control=$arg
        else
            server_name=${arg,,}
        fi
    done
    echo "$server_name:$port:$protocol:$access_control"
}


# wget wrapper
wget_wrapper(){
   local proto=$1
   local server=$2
   local port=$3
   local res=1
   local ret_val=1

   timeout $((TIMEOUT_DURATION+1)) wget --spider --no-check-certificate -q  --timeout=$TIMEOUT_DURATION $proto://$server:$port
   res=$?

   case $res in
     0)
     ret_val=0
     ;;
     1)
     echo -e "WARNING\tWget Generic error code"
     ret_val=1
     ;;
     2)
     echo -e "WARNING Wget\tWget Parse Error (initialization)"
     ret_val=1
     ;;
     3)
     echo -e "WARNING\tWget File I/O error "
     ret_val=1
      ;;
     4)
     echo -e "WARNING\tWget Network failure."
     ret_val=1
      ;;
     5)
     echo -e "WARNING\tWget SSL verification failure."
     ret_val=0
      ;;
     6)
     echo -e "WARNING\tWget Username/password authentication failure."
     ret_val=0
     ;;
     7)
     echo -e "WARNING\tWget Protocol errors."
     ret_val=1
     ;;
     8)
     echo -e "WARNING\tWget Remote server issued an error response."
     ret_val=0
     ;;
     *)
     echo -e "WARNING\tWget unknown response code"
     ret_val=1
     ;;
   esac
   return $ret_val
}


# Function to test connectivity
test_connectivity() {
    local server=$1
    local port=$2
    local protocol=$3
    local expected_result=$4

    if [ "$protocol" == "ICMP" ]; then
        timeout $TIMEOUT_DURATION ping -c 1 $server > /dev/null 2>&1
    elif [ "$protocol" == "UDP" ]; then
        timeout $TIMEOUT_DURATION bash -c "echo > /dev/udp/$server/$port" 2>/dev/null
    elif [ "$protocol" == "HTTP" ]; then
         wget_wrapper 'http' $server $port
    elif [ "$protocol" == "HTTPS" ]; then
         wget_wrapper 'https' $server $port
    else
        timeout $TIMEOUT_DURATION bash -c "echo > /dev/tcp/$server/$port" 2>/dev/null
    fi

    if [ $? -eq 0 ]; then
        actual_result="ALLOW"
        textual_result="allowed"
    else
        actual_result="DENY"
        textual_result="denied"
    fi

    if [ "$actual_result" == "$expected_result" ]; then
        echo -e "PASS\tConnection to $server on port $port using $protocol is $textual_result" | tee -a $LOGFILE
    else
        echo -e "FAILED\tConnection to $server on port $port using $protocol is $textual_result (expected $expected_result)" | tee -a $LOGFILE
    fi
}

# Function to check DNS resolution
check_dns() {
    local server=$1
    if ! [[ $server =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if ! getent hosts "$server" > /dev/null; then
            return 1
        fi
    fi
    return 0
}

# main function
function main(){
  while IFS=: read -r arg1 arg2 arg3 arg4; do
      [[ -z "$arg1"  ]] && continue
      if [[ "$arg1" =~ ^[[:space:]]*# ]]; then
          echo "$arg1 $arg2 $arg3 $arg4" | tee -a $LOGFILE
          continue
      fi
  
      result=$(identify_arguments "$arg1" "$arg2" "$arg3" "$arg4")
      IFS=: read -r server port protocol expected_result <<< "$result"
  
      if check_dns $server; then
          test_connectivity $server $port $protocol $expected_result
      else
          echo -e "WARNING\tSkipping $server due to DNS resolution failure" | tee -a $LOGFILE
      fi
  done < "$FILENAME"
}


# script bootstrap 
# Check for required commands
check_commands

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 filename"
    exit 1
fi

# Log start time
start_time=$(date +"%Y-%m-%d %H:%M:%S")
echo "# Starting test at $start_time" | tee $LOGFILE
hostname | sed 's/^/# /'
ip -br address | sed 's/^/# /'
echo '#'

echo '# Showing possible proxy available for HTTP/HTTPS tests with wget'
env  | grep proxy | sed 's/^/# /'
echo '#'

main

# Log stop time
stop_time=$(date +"%Y-%m-%d %H:%M:%S")
echo "# Stopping tests at $stop_time" | tee -a $LOGFILE
echo "# Find logs in $LOGFILE"
