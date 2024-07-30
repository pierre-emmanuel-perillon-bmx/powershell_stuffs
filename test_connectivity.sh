
#!/bin/bash
FILENAME=$1
LOGFILE="log_connectivity.log"
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
            echo -e "ERROR\t$cmd is not installed." 1>&2 
            exit 1
        fi
    done
}


# Function to match arguments.
identify_arguments() {
    local args_up=("${1^^}" "${2^^}" "${3^^}" "${4^^}" "${5^^}")
    local args_ori=("$1" "$2" "$3" "$4" "$5")
    local mixed="$DEFAULT_PORT"
    local protocol="$DEFAULT_PROTOCOL"
    local access_control="$DEFAULT_ACCESS"
    local server_name="$DEFAULT_SERVER"
    local value=''
    local with_proxy='Y'

    #lets iterate over table keys.
    for i in "${!args_up[@]}"; do
        value="${args_up[i]}"
        if [ 'URL' = "$protocol" ]; then
            if [[ $value =~ ^(ALLOW|DENY)$ ]]; then
                access_control="$value"
            elif [ 'NO_PROXY' == "$value" ]; then
                with_proxy='N'
            elif [[ -n  $value ]]; then
                echo -e "WARNING\tIgnoring $value." 1>&2
            fi
        else
            #it can be a regular url (low formal check)
            #it can match a number
            #magic word
            #should be server name (but not empty)
            if [[ $value =~ ^(\"|\')?HTTPS?:// ]]; then
                server_name=$(echo "$value" | sed -E 's|https?://([^:/]+).*|\1|')
                mixed="${args_ori[i]}"
                protocol='URL'
            elif [ 'NO_PROXY' == "$value" ]; then
                with_proxy='N'
            elif [[ $value =~ ^[0-9]+$ ]]; then
                #port number
                mixed=$value 
            elif [[ $value =~ ^(TCP|UDP|ICMP|HTTP|HTTPS)$ ]]; then
                protocol=$value
            elif [[ $value =~ ^(ALLOW|DENY)$ ]]; then
                access_control=$value
            elif [[ -n  $value ]]; then
                server_name=$value
            fi
        fi
    done

    #we want lowercase server_name
    server_name=${server_name,,}

    #to simplify downstream ...
    if [[ $protocol =~ ^HTTP ]];then
        value="${protocol,,}://$server_name:$mixed"
        mixed=$value
        protocol='URL'
    fi

    echo "$access_control $protocol $server_name $mixed $with_proxy"
}



# wget wrapper
wget_wrapper(){
    local server=$1
    local url=$2
    local proxy=$3
    local res=1
    local ret_val=1
    local proxy_opt=''

    if [ 'N' = "$proxy" ] ; then
        $proxy_opt='--no-proxy'
    fi
    
    timeout $((TIMEOUT_DURATION+1)) wget --spider --no-check-certificate -q $proxy_opt --timeout=$TIMEOUT_DURATION $url
    res=$?
    
   case $res in
   0)
        ret_val=0
        ;;
   1)
        echo -e "WARNING\tWget Generic error code #$res when connecting to $server." | tee -a $LOGFILE 1>&2
        ret_val=1
        ;;
   2)
        echo -e "WARNING Wget\tWget Parse Error (initialization) #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=1
        ;;
   3)
        echo -e "WARNING\tWget File I/O error #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=1
        ;;
   4)
        echo -e "WARNING\tWget Network failure #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=1
        ;;
   5)
        echo -e "WARNING\tWget SSL verification failure #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=0
        ;;
   6)
        echo -e "WARNING\tWget Username/password authentication failure #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=0
        ;;
   7)
        echo -e "WARNING\tWget Protocol errors #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=1
        ;;
   8)
        echo -e "WARNING\tWget Remote server issued an error response #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=0
        ;;
    124) echo -e "WARNING\tWget was too slow to connect to $server."  | tee -a $LOGFILE 1>&2
        ret_val=1
        ;;
   *)
        echo -e "WARNING\tWget unknown response code #$res when connecting to $server."  | tee -a $LOGFILE 1>&2
        ret_val=1
        ;;
   esac
   return $ret_val
}

#function to summarize an url for easier display
summarize_url() {
    local url=$1
    local protocol=$(echo "$url" | grep -oE '^[^:]+')
    local temp=${url#*://}
    local server=$(echo "$temp" | sed -E 's|([^:/]+).*|\1|')
    temp=${temp#"$server"}
    local port=$(echo "$temp" | grep -oE '^:[0-9]+' | sed 's/://')
    temp=${temp#":$port"}
    if [[ "$protocol" == "http" && "$port" == "80" ]] || [[ "$protocol" == "https" && "$port" == "443" ]]; then
        port=""
    else 
        port=":$port"
    fi
    local query="$temp"
    if [[ ${#query} -gt 24 ]]; then
        query="${query:0:12}....${query: -8}"
    fi
    echo "$protocol://$server$port$query"
}

# Function to test connectivity
test_connectivity() {
    local expected_result=$1
    local protocol=$2
    local server=$3
    local mixed=$4
    local proxy=$5
    local proto=${protocol,,}
    local message=''

    case "$protocol" in
        ICMP)
            message="Connection to $server using $protocol"
            timeout $TIMEOUT_DURATION ping -c 1 $server > /dev/null 2>&1
            ;;
        TCP|UDP)
            message="Connection to $server using $protocol on port $mixed"
            timeout $TIMEOUT_DURATION bash -c "echo > /dev/$proto/$server/$mixed" 2>/dev/null
            ;;
        URL)

            message="Connection to $(summarize_url $mixed) (proxy=$proxy)"
            wget_wrapper $server $mixed $proxy 
            ;;
        *)
            echo -e "ERROR\tProtocol $protocol is not managed for $server"  | tee -a $LOGFILE 1>&2 
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        actual_result="ALLOW"
        textual_result="allowed"
    else
        actual_result="DENY"
        textual_result="denied"
    fi

    if [ "$actual_result" == "$expected_result" ]; then
        echo -e "PASS\t$message is $textual_result" | tee -a $LOGFILE
    else
        echo -e "FAILED\t$message is $textual_result (expected $expected_result)" | tee -a $LOGFILE
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
    local line
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            echo "$line" | tee -a $LOGFILE
            continue
        fi
        
        result=$(identify_arguments $line)
        IFS=' ' read -r access_control protocol server_name mixed proxy<<< "$result"
        
        if ([ "$protocol" == "URL" ] && [ "$proxy" == "Y" ]) || check_dns "$server_name"; then
            test_connectivity "$access_control" "$protocol" "$server_name" "$mixed" "$proxy"
        else
            echo -e "WARNING\tSkipping $server_name due to DNS resolution failure" | tee -a $LOGFILE 1>&2
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

echo '# Showing possible proxy available for HTTP/HTTPS tests with wget' li
env  | grep proxy | sed 's/^/# /'
echo '#'

main

# Log stop time
stop_time=$(date +"%Y-%m-%d %H:%M:%S")
echo "# Stopping tests at $stop_time" | tee -a $LOGFILE
echo "# Find logs in $LOGFILE"

