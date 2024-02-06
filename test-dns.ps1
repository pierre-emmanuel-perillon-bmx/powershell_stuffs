
$INI_OUTFILE = 'dns.txt'

$urls=@(

##list your domains here.

)


$script:CACHE_DNS=@{}


function resolve-domain( [string] $domain, [Array] $list = @() )
    $fix = $domain.ToLower().Trim()
    if ( $list -contains $fix ){
        Write-Information "# cutting infinite loop"
        return
    }

    $listed = @($fix)+$list
    $ttt = read-cache $fix 
    if ( $ttt -eq $null ){
        $rec = Resolve-DnsName -Name $fix  -ErrorAction Ignore
    }
    else {
        $rec = $ttt 
    }

    if ( $rec -is 'System.Array' ){
        foreach( $sub in $rec ){
            if ( $sub -is [Microsoft.DnsClient.Commands.DnsRecord] ) {
                push-tocache $sub
            }
        }
        foreach( $sub in $rec ){
            if ( $x -is [Microsoft.DnsClient.Commands.DnsRecord] ) {
                recurse-record $sub $listed
            }
        }#foreach
    }
    elseif ( $rec -is [Microsoft.DnsClient.Commands.DnsRecord] ){
        recurse-record $rec $listed
    }
    else {
        write "#   $fix-me "
    }
}


function push-tocache( [Microsoft.DnsClient.Commands.DnsRecord]  $rec ){
    $key = $rec.Name
    if ( $script:CACHE_DNS.Contains($key) ){
        #
    }else{
        $script:CACHE_DNS.Add($key,$rec)| Out-Null
    }
}


function read-cache($query){
    $q =$query 
    $active = $thread
    if ($script:CACHE_DNS.Containskey($q)){
        return $script:CACHE_DNS[$q]
    }
    return $null 
}


function recurse-record([Microsoft.DnsClient.Commands.DnsRecord] $rec , [Array] $thread ){
    switch( $rec.Type ){
        'CNAME'{ 
            resolve-domain $rec.NameHost $thread 
        }
        'PTR'{
            resolve-domain $rec.NameHost $thread 
        }
        'A'{
            print-DNS $rec $thread
        }
        'AAAA'{
            print-DNS $rec $thread
        }
        Default {
            Write-Output "# unamaged $($sub.Type) result for $fix"
        }
    }#switch
}


function print-DNS([Microsoft.DnsClient.Commands.DnsRecord] $rec , [Array] $thread  ){
    $ip = $rec.IPaddress 
    $name =  $rec.name
    $many = $thread -join ' ' 

    if ([string]::IsNullOrEmpty($ip)){
        Write-Output "#    $request"
    } 
    elseif ( $thread -contains  $rec.name ){
        Write-Output "$ip   $many "        
    }
    else {
        Write-Output "$ip   $name $many"
    }
}


#| Sort-Object -Unique 
$urls| ForEach-Object {
    Resolve-domain $_ 
} | Out-File  $INI_OUTFILE 

