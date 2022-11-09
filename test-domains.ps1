$urls=@(

##list your domains here.

)


Clear-DnsClientCache

function test-domains ( [string] $url, [string] $site ){

Process{
    $webhost = $location = $StatusCode = $StatusDescription = '------'
    Write-host -NoNewline "$url  "
    try{
        $Response=Invoke-WebRequest -Uri $url  -UseBasicParsing -MaximumRedirection 0 -ErrorAction SilentlyContinue 
        ##Microsoft.PowerShell.Commands.BasicHtmlWebResponseObject 
        $StatusCode = $Response.StatusCode
        $StatusDescription= $Response.StatusDescription 
        if ([string]::IsNullOrEmpty( $Response.Headers.Location)) {$location = $site }else {$location=$Response.Headers.Location} 
        #if ([string]::IsNullOrEmpty($Response.BaseResponse)) {$webhost=$site}else { $webhost=$Response.BaseResponse.ResponseUri.Host }

    }catch {
        $Response=$_.Exception.Response
        #System.Net.WebResponse 
        if ( [string]::IsNullOrEmpty($Response)){
            ##not answer
            $StatusCode=-1 
            $StatusDescription = $_.Exception.Message
            $location=''
            #$webhost=''
        }else {
            $StatusCode = [int][System.Net.HttpStatusCode]::$($Response.StatusCode)
            $StatusDescription=  $Response.StatusDescription
            if( [string]::IsNullOrEmpty($Response.GetResponseHeader('location')) ) {$location = $site} else { $location = $Response.GetResponseHeader('location') }
            #if( [string]::IsNullOrEmpty($Response.BaseResponse) )  {$webhost = $site}  else { $webhost = $Response.BaseResponse.ResponseUri.Host}                    
 
        }
    }


    if ( $StatusCode -eq -1 ){
        Write-host  -ForegroundColor Red  "(a) $StatusCode Can not connect on remote -> $StatusDescription"
    }
    elseif ( $location -ne $site  ){
        Write-host  -ForegroundColor Yellow  "(b) $StatusCode  $StatusDescription => $location  "
    }
    elseif ( $StatusCode -ne 200 ){
        Write-host -ForegroundColor Yellow "(c) $StatusCode  $StatusDescription => $location "

    }
    else {
        write-host "(d) $StatusCode  $StatusDescription "
    }
    
    if ( $Response -is [System.Net.HttpWebResponse] ){
        $msg = $Response.GetResponseHeader('Served-By')
        Write-Host -ForegroundColor Yellow "## served-by : $msg "    
    }
    #elseif ( $Response -is [Microsoft.PowerShell.Commands.WebResponseObject] ){
    #    $msg = $Response.BaseResponse.GetResponseHeader('Server')
    #    Write-Host -ForegroundColor Yellow "## served-by : $msg " 
    #}
 }#process
}#function


$urls| Sort-Object -Unique | ForEach-Object {
    $site = $_ 


    $url = 'https://{0}/' -f $site 
    test-domains $url  $site 

 #   $url = 'http://{0}/' -f $site 
 #   test-domains $url $site 


}
