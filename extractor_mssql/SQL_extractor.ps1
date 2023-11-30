param(
    [Parameter(Position=0,mandatory=$true)][string][ValidateSet('explicit','all','negate')] $mode , #= 'explicit'
    [switch] $dump_base,
    [switch] $archive
 
)

$INI_ROOT = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$INI_DB_CONFIG_FILE        ='config.xml'
$INI_OUTPUT_PATH           ='C:\dump\data'
$INI_OUTPUT_TABLE_SIZE     ='{0}\report_database_tables_size.csv'  
$INI_OUTPUT_DUMP_RAW       ='{0}\bmx_ipmanager_{1}.csv'
$INI_OUTPUT_FLAG           ='{0}\refresh_on_going' -f $INI_OUTPUT_PATH
$INI_COMPRESSION_LEVEL     ='Fastest'  # Optimal
$INI_WAIT_SECOND           =2
$INI_QUERY_RELEVANT_TABLES ='query_list_all_tables.sql'
$INI_QUERY_SELECT          ='query_select_start_cast.sql'
$INI_QUERY_TABLESIZE       ='query_about_tablesize.sql'
$INI_TIMESTAMP_FORMAT      ='yyyyMMddHHmmss'

$RUNTIME_CHOICE=@{
    'dump_ipmanager'       =$dump_master
    'archive'              =$archive
}


function action-or-skip ([string] $query ){
    if ( $mode -eq 'all' ){
        return $true 
    }
    if ( $mode -eq 'negate' ) {
        if ( $RUNTIME_CHOICE.Contains($query) ){
            return -not($RUNTIME_CHOICE[$query])
        }
        else{
            return $true
        }
    }
    if ( $RUNTIME_CHOICE.Contains($query) ){
        return $RUNTIME_CHOICE[$query]
    }
    else{
        return $false 
    }
}


function archive-or-remove( [string]$path ){
    if ( ($RUNTIME_CHOICE['archive']) -and ( Test-Path $path ) ){
        $tmp= get-item $path 
        $ext=$tmp.LastWriteTime.ToString($INI_TIMESTAMP_FORMAT)
        $dst =$tmp.DirectoryName+'\'+$tmp.BaseName+'-'+$ext+$tmp.Extension
        Move-Item -Verbose -Path $path -Destination $dst     
    }
}

function read-file-query ([string] $filename) {
    return Get-Content (join-path  $INI_ROOT  $filename )
}

function establish-connexion(){
    try{
        #pas de xpath, on se contente de convertir le xml en object powershell et ensuite on parcours à la mano & en dur.
        [xml]$config_xml = Get-Content (join-path  $INI_ROOT  $INI_DB_CONFIG_FILE )
        $connection_string = $config_xml.connectionStrings.add.Attributes['connectionString'].value
    }catch{
        $Error = $_.Exception.Message 
        $msg="Can not retrieve connexion file and connection_string, giving up"
        Write-Output $msg
        Write-Error $msg 
        Write-Error $Error 
        exit 1 
    }


    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    try{
        $SqlConnection.ConnectionString = $connection_string 
        $SqlConnection.Open();
    }catch{
        $Error = $_.Exception.Message 
        $msg="Can not retrieve open database, giving up"
        Write-Output $msg
        Write-Error $msg 
        Write-Error $Error 
        exit 1
    }
    return $SqlConnection 
}

function execute-sqlselectquery1 ([System.Data.SqlClient.SqlConnection]$SqlConnection,[string] $SqlStatement, [hashtable]$sqlparameters, [string] $path ){
    $ErrorActionPreference = "Stop"
    
    archive-or-remove $path 

    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $sqlCmd.Connection = $sqlConnection
    $sqlCmd.CommandText = $SqlStatement
   
    foreach ($h in $sqlparameters.GetEnumerator()) {
        $SqlCmd.parameters.AddWithValue( "@"+$h.Name, $h.value) | out-null 
    }

    $sqlAdapter = New-Object System.Data.SqlClient.SqlDataAdapter
    $sqlAdapter.SelectCommand = $sqlCmd
    $data = New-Object System.Data.DataSet
    try
    {
        $sqlAdapter.Fill($data) 
        $data.Tables[0] | ConvertTo-Csv  -NoTypeInformation | Out-File -FilePath "$path" -Encoding default
    }
    catch
    {
        $Error = $_.Exception.Message
        Write-Error $Error
        Write-Error -Verbose "Error executing SQL on database [$Database] on server [$SqlServer]. Statement: `r`n$SqlStatement"
    }
    finally {
       # $sqlAdapter.Dispose()
    }
}

function execute-sqlselectquery2( [System.Data.SqlClient.SqlCommand]$SqlCmd, [string]$sqlText , [hashtable]$sqlparameters ){
    foreach ($h in $sqlparameters.GetEnumerator()) {
        $SqlCmd.parameters.AddWithValue( "@"+$h.Name, $h.value) | out-null 
    }

    if ( [String]::IsNullOrEmpty($sqlText) -eq $false ){
        $SqlCmd.CommandText = $sqlText
    }

    $dataReader =  $SqlCmd.ExecuteReader()
    $resulttype=$dataReader.GetType().Name
    $result= @{}

    if ( $resulttype -eq 'SqlDataReader' ) {
        $columns_name = New-Object Collections.Generic.List[string]
        
        $line=0
        for($i=0;$i -lt $dataReader.VisibleFieldCount;$i++){
            $columns_name.add($dataReader.GetName($i) ) | out-null 
        }
        while( $dataReader.Read() ){
            $row = New-object psobject 
            foreach($col in $columns_name){
                add-member -InputObject $row -MemberType NoteProperty -Name $col -Value $dataReader[$col]|out-null 
            }
            $result.add($line,$row)|out-null
            $line++
        }#while

    }else{
        Write-Error -Category InvalidType 'looks like a bug, sorry'
    }

    $dataReader.close() 
    return $result  

}

function export ([hashtable] $t, $file ){

    archive-or-remove $file 

    if ( $t -eq $null -or $t.Count -eq 0 ){
        Write-Output "   -> no results"
        "" | Out-File $file -Encoding default
        return
    }
    $t[0] | ConvertTo-Csv -NoTypeInformation -Delimiter ";" |  Select-Object -First 1 | Out-File $file -Encoding default 
    $t.GetEnumerator() | ForEach-Object {
        $_.Value | ConvertTo-Csv -NoTypeInformation -Delimiter ";"   | Select-Object -Skip 1    | Out-File -Append $file -Encoding default 
    } 
    
}


function perform-onequery-report([System.Data.SqlClient.SqlConnection]$SqlConnection,[string]$title,[string]$sql,[hashtable]$param,[string]$path){
    Write-Output $title 
    Write-Output "   ->$path"
    try {
        execute-sqlselectquery1 $SqlConnection $sql $param $path 
#       $all_results = execute-sqlselectquery2 $SqlCmd $sql $param 
#		export $all_results $path 
    }catch {
        $Error = $_.Exception.Message
        Write-Error $Error
    }
}


function dump_ipmanager([System.Data.SqlClient.SqlConnection]$SqlConnection) {
    dump_e2sDatabase $SqlConnection $INI_QUERY_RELEVANT_TABLES #'ipmanager_all_tables'
}


function dump_e2sDatabase([System.Data.SqlClient.SqlConnection]$SqlConnection, $sql_script,[string] $zipname = '' ) {
    #create report table
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection

    $SqlCmd.CommandText = 'SET ANSI_NULLS ON'
    $SqlCmd.ExecuteNonQuery() | out-null 

    $SqlCmd.CommandText = 'SET QUOTED_IDENTIFIER ON'
    $SqlCmd.ExecuteNonQuery() | out-null 
    
    $sql = read-file-query $sql_script
    $sqlTemplate = read-file-query $INI_QUERY_SELECT

    $intermediate = execute-sqlselectquery2 $SqlCmd $sql @{}

    Write-Output "Found $($intermediate.count) items"
    if ( [string]::IsNullOrEmpty($zipname) ){
        Write-Output "Dumped item will be zipped "
        $do_zip=$false
    }else{
        Write-Output "Dumped item will not be zipped "
        $zip_fqln = $INI_OUTPUT_DUMP_RAW -f $INI_OUTPUT_PATH,$zipname
        $zip_fqln = $zip_fqln + '.zip'
        $do_zip=$true
        archive-or-remove $zip_fqln 
        if ( Test-Path $zip_fqln ){
            Remove-Item -Verbose $zip_fqln
        }
    }

    $intermediate.GetEnumerator() | ForEach-Object {
        $active_table = $_.value
        
        $title="Dumping table {0} " -f $active_table.express
        
        $sql = $sqlTemplate -f $active_table.express
        #$sqlCmd.CommandText = $sql

        $tmp = $active_table.DatabaseName+'-'+$active_table.SchemaName+'-'+$active_table.TableName
        $path = $INI_OUTPUT_DUMP_RAW -f $INI_OUTPUT_PATH,$tmp 

        Write-Output $title 
        execute-sqlselectquery1 $SqlConnection $sql @{} $path

        #manage zip file immediatily
        if ( $do_zip ) {
            move-tozip  $path $zip_fqln 
        }
        Start-Sleep -s $INI_WAIT_SECOND 
    }
}

function move-tozip ([string] $path ,[string] $zip_fqln ){
    if ( Test-Path -Path $zip_fqln -PathType leaf )  {
        Write-Output "Add $path to $zip_fqln"
        Compress-Archive -Path $path -DestinationPath $zip_fqln -Update -CompressionLevel $INI_COMPRESSION_LEVEL
    }else{
        Write-Output "Create $path to $zip_fqln"
        Compress-Archive -Path $path  -DestinationPath $zip_fqln -CompressionLevel  $INI_COMPRESSION_LEVEL
    }
    Remove-Item -LiteralPath $path -Recurse 
}

function main (){
    $sqlconnection = establish-connexion

    #put a flag
    'go' | Out-File $INI_OUTPUT_FLAG -Force


   # other file 
    $title="About table size"
    if  (action-or-skip $title){
	    $path = $INI_OUTPUT_TABLE_SIZE -f $INI_OUTPUT_PATH
 	    $param = @{}
        $sql = read-file-query $INI_QUERY_TABLESIZE
	    perform-onequery-report $SqlConnection $title $sql $param $path 
    }
    

    $title = 'dump_ipmanager'
    if  (action-or-skip $title){
        dump_ipmanager $SqlConnection
    }


	Write-Output "Ending script"

    $sqlconnection.close() | Out-Null


    Remove-Item -Path $INI_OUTPUT_FLAG 


    Write-Output "see you soon"
}

main


exit 0 


<##
# INSERT INTO [#MONITOR_CCS_STATUS] ([Schema],[Tablename],[compagny],[CCS_ID],[CCS_KEY],[CCS_CCM_CODE],[CCS_CCM_NAME],[CCS_USR_LOGIN],[CCS_USR_NAME],[CCS_DATE],[CCS_STATUS],[CCS_COMMENT],[CCS_FILE]) 
#  SELECT @SCHEMANAME,@FULLNAME,@LABEL,[CCS_ID],[CCS_KEY],[CCS_CCM_CODE],[CCS_CCM_NAME],[CCS_USR_LOGIN],[CCS_USR_NAME],[CCS_DATE],[CCS_STATUS],[CCS_COMMENT],[CCS_FILE] 
#  FROM {0} x 
#  WHERE not ( ccs_usr_login = '' and ccs_status = 1 )
##
function fill-temporarytable([hashtable] $tableslist,[System.Data.SqlClient.SqlConnection]$SqlConnection){
    if ( $tableslist -eq $null -or $tableslist.count -eq 0 ) {
        Write-Warning "No table to stage"
        return 
    }

    $sqlTemplate = read-file-query 'query_insert_into_temptable.sql'

    #Write-Output $tableslist

    $tableslist.GetEnumerator() | ForEach-Object {
        $active_table = $_.value 

        $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $SqlConnection

        $sql = $sqlTemplate -f $active_table.FULLNAME
        $sqlCmd.CommandText = $sql
        $sqlCmd.Parameters.AddWithValue('@SCHEMANAME',$active_table.SCHEMANAME ) | Out-Null
        $sqlCmd.Parameters.AddWithValue('@FULLNAME'  ,$active_table.FULLNAME )   | Out-Null
        $sqlCmd.Parameters.AddWithValue('@LABEL'     ,$active_table.CPY_LABEL )  | Out-Null


        try {
            $r=$sqlCmd.ExecuteNonQuery()
            Write-Output "staged $($active_table.FULLNAME) with $r records over $($active_table.ROWS_COUNT) found."
        }catch {
            $Error = $_.Exception.Message
            Write-Error $Error
            write-error "issue during $($active_table.FULLNAME) setup"
        }
    } #each table
}
#>