param(
    [switch] $dont_dump_base, #allow to not perform the main dump if set
    [switch] $dont_archive,   #files will be deleted if set
    [switch] $do_all,         #not used
    [switch] $sign            #signature file will be generated at the end of the process
)

$INI_ROOT = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$INI_DB_CONFIG_FILE        ='config.xml'
$INI_OUTPUT_PATH           ='C:\dump\data'
$INI_OUTPUT_INZIP          ='' #put a valide file name here to zip file while extracting. 
$INI_OUTPUT_SIGNATURE      ='{0}\signature.txt'
$INI_OUTPUT_TABLE_SIZE     ='{0}\report_database_tables_size.csv'  
$INI_OUTPUT_DUMP_RAW       ='{0}\application_{1}.csv'
$INI_OUTPUT_FLAG           ='{0}\refresh_on_going' -f $INI_OUTPUT_PATH

$INI_COMPRESSION_LEVEL     ='Fastest'  # Fastest vs Optimal
$INI_WAIT_SECOND           =2          # wait enough to let server breath
$INI_TIMESTAMP_FORMAT      ='yyyyMMddHHmmss'

$INI_QUERY_RELEVANT_TABLES ='query_list_all_tables.sql'
$INI_QUERY_SELECT          ='query_select_start_cast.sql'
$INI_QUERY_TABLESIZE       ='query_about_tablesize.sql'

$RUNTIME_CHOICE=@{
    '_archive'              =!$dont_archive
    '_default'              =$do_all 
    '_dump'                 =!$dont_dump_base
    '_signature'            =$sign 
    'About table size'      =$true
}


function action-or-skip ([string] $query ){
    if ( $RUNTIME_CHOICE.Contains($query) ){
        return $RUNTIME_CHOICE[$query]
    }
    else{
        return $RUNTIME_CHOICE['_default']
    }
}


function archive-or-remove( [string]$path ){
    if ( Test-Path $path ) {
        if ($RUNTIME_CHOICE['_archive']){
            $tmp= get-item $path 
            $ext=$tmp.LastWriteTime.ToString($INI_TIMESTAMP_FORMAT)
            $dst =$tmp.DirectoryName+'\'+$tmp.BaseName+'-'+$ext+$tmp.Extension
            Move-Item -Verbose -Path $path -Destination $dst     
        }
        else {
            remove-item -Verbose -Path $path 
        }
    }
}


function read-file ([string] $filename) {
    return Get-Content (join-path  $INI_ROOT  $filename )
}


function establish-connexion(){
    try{
        #pas de xpath, on se contente de convertir le xml en object powershell et ensuite on parcours à la mano & en dur.
        [xml]$config_xml = read-file  $INI_DB_CONFIG_FILE
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
    try{
        $sqlAdapter.Fill($data) 
        $data.Tables[0] | ConvertTo-Csv  -NoTypeInformation | Out-File -FilePath "$path" -Encoding default
    }
    catch{
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
#       export $all_results $path 
    }catch {
        $Error = $_.Exception.Message
        Write-Error $Error
    }
}


function dump_database([System.Data.SqlClient.SqlConnection]$SqlConnection, $sql_script,[string] $zipname = '' ) {
<#
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection

    $SqlCmd.CommandText = 'SET ANSI_NULLS ON'
    $SqlCmd.ExecuteNonQuery() | out-null 

    $SqlCmd.CommandText = 'SET QUOTED_IDENTIFIER ON'
    $SqlCmd.ExecuteNonQuery() | out-null 
#>
    $sql = read-file $sql_script
    $sqlTemplate = read-file $INI_QUERY_SELECT

    $intermediate = execute-sqlselectquery2 $SqlCmd $sql @{}

    Write-Output "Found $($intermediate.count) items"
    if ( [string]::IsNullOrEmpty($zipname) ){
        Write-Output "Dumped item will not be zipped "
        $do_zip=$false
    }else{
        Write-Output "Dumped item will be zipped "
        $zip_fqln = $INI_OUTPUT_DUMP_RAW -f $INI_OUTPUT_PATH,$zipname
        $zip_fqln = $zip_fqln + '.zip'
        $do_zip=$true
        archive-or-remove $zip_fqln 
    }

    $intermediate.GetEnumerator() | ForEach-Object {
        $active_table = $_.value
        $title="Dumping table {0} " -f $active_table.express
        $sql = $sqlTemplate -f $active_table.express
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
    'running' | Out-File $INI_OUTPUT_FLAG -Force

    $title="About table size"
    if  (action-or-skip $title){
        $path = $INI_OUTPUT_TABLE_SIZE -f $INI_OUTPUT_PATH
        $param = @{}
        $sql = read-file $INI_QUERY_TABLESIZE
        perform-onequery-report $SqlConnection $title $sql $param $path 
    }
    
    ##add custom query here as "About table size" 
    #$title="title"
    #if  (action-or-skip $title){
    #    $path = '{0}\report....csv' -f $INI_OUTPUT_PATH
    #    $param = @{}
    #    $sql = read-file 'query....sql'
    #    perform-onequery-report $SqlConnection $title $sql $param $path 
    #}

    $title = '_dump'
    if  (action-or-skip $title){
        dump_database $SqlConnection $INI_QUERY_RELEVANT_TABLES $INI_OUTPUT_INZIP 
    }

    Write-Output "Ending extraction"
    $sqlconnection.close() | Out-Null
    Remove-Item -Path $INI_OUTPUT_FLAG 

    $title = '_signature'
    if  (action-or-skip $title){
        write-output 'Perform hash signature'
        $tmp = $INI_OUTPUT_SIGNATURE -f $INI_OUTPUT_PATH
        Get-ChildItem $INI_OUTPUT_PATH| Get-FileHash > $tmp 
    }

    Write-Output "see you soon"
}


main

exit 0 
