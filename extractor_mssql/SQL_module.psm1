<#

$INI_COMPRESSION_LEVEL     ='Fastest'  # Fastest vs Optimal
$INI_WAIT_SECOND           =2          # wait enough to let server breath
$INI_TIMESTAMP_FORMAT      ='yyyyMMddHHmmss'
$INI_ROOT                  =[System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$INI_QUERY_SELECT          ='query_select_start.sql'
$INI_QUERY_TABLESIZE       ='query_about_tablesize.sql'
$INI_QUERY_TABLES2COPY     ='query_e2sv6_tablestomove.'

$INI_OUTPUT_INZIP          ='' #put a valide file name here to zip file while extracting. 
$INI_OUTPUT_SIGNATURE      ='{0}\signature.txt'
$INI_OUTPUT_TABLE_SIZE     ='{0}\report_database_tables_size.csv'  
$INI_OUTPUT_DUMP_RAW       ='{0}\application_{1}.csv'
$INI_OUTPUT_FLAG           ='{0}\refresh_on_going' -f $INI_OUTPUT_PATH
$INI_QUERY_TABLES2CLEAR
#>

$script:RUNTIME_CHOICE         =$RUNTIME_CHOICE
$script:INI_TIMESTAMP_FORMAT   =$INI_TIMESTAMP_FORMAT
$script:INI_COMPRESSION_LEVEL  =$INI_COMPRESSION_LEVEL
$script:INI_QUERY_TABLES2CLEAR =$INI_QUERY_TABLES2CLEAR
$script:INI_QUERY_TABLES2COPY  =$INI_QUERY_TABLES2COPY
$script:INI_QUERY_SELECT       =$INI_QUERY_SELECT
$script:INI_OUTPUT_DUMP_RAW    =$INI_OUTPUT_DUMP_RAW
$script:INI_OUTPUT_PATH        =$INI_OUTPUT_PATH
$script:INI_WAIT_SECOND        =$INI_WAIT_SECOND
$script:INI_ROOT               =$INI_ROOT 
$script:INI_DELIMITER          =';'

function backup-previousfile( [string]$path ){
    if ( Test-Path $path ) {
        if ($script:RUNTIME_CHOICE['_archive']){
            $tmp= get-item $path 
            $ext=$tmp.LastWriteTime.ToString($script:INI_TIMESTAMP_FORMAT)
            $dst =$tmp.DirectoryName+'\'+$tmp.BaseName+'-'+$ext+$tmp.Extension
            Move-Item -Verbose -Path $path -Destination $dst     
        }
        else {
            remove-item -Verbose -Path $path 
        }
    }
}


function confirm-action ([string] $query){
    if ( $script:RUNTIME_CHOICE.Contains($query) ){
        return $script:RUNTIME_CHOICE[$query]
    }
    else{
        return $script:RUNTIME_CHOICE['_default']
    }
}


function convert-toArray {
  begin {
    $output = @();
  }
  process {
    $output += $_;
  }
  end {
    return ,$output;
  }
}


function copy-tablewithidentity ([System.Data.SqlClient.SqlConnection]$SqlConnection,[string] $write_table , [string] $read_table,[boolean] $delete, [boolean] $noidentity ){
    
    $off_template = 'SET IDENTITY_INSERT {0} OFF;'
    $on_template =  'SET IDENTITY_INSERT {0} ON;'
    $col_template = 'SELECT ''[''+name+'']'' FROM sys.columns WHERE object_id = OBJECT_ID(@tablename) '
    $delete_template = 'DELETE FROM {0} '
    $insert_template =@'
insert 
  INTO {0}(
     {1}
  )
select {1}
  FROM {2};
'@

    #1 make list of fields
    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $sqlCmd.Connection = $sqlConnection
    
    $cols=invoke-sqlselectquery3 $sqlCmd $col_template @{'tablename'=$write_table} 
    $tmp = $cols.Values | convert-toArray 
    $fieldlist = $tmp -join ','

    #printout 
    Write-Output '-----'
    if ( -not ( $noidentity ) ) {   
        $on_template -f $write_table | Write-Output
    }
    if ( $delete ){ 
        $delete_template -f $write_table | Write-Output
    }
    $insert_template -f $write_table, $fieldlist, $read_table | Write-Output
    if ( -not ( $noidentity ) ) { 
        $off_template -f $write_table  | Write-Output   
    }
    Write-Output ''
}


function copy-tablefromAnotherSchemaWithIdentity([System.Data.SqlClient.SqlConnection]$SqlConnection,[string] $tablename, [string] $write_schema ,[string] $read_schema , [switch] $delete, [switch] $noidentity ){
    $read = "$read_schema.$tablename"
    $write  = "$write_schema.$tablename"
    copy-tablewithidentity $SqlConnection  $write  $read $delete $noidentity 
}


##
function clear-database([System.Data.SqlClient.SqlConnection]$SqlCnn ) {
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlCnn
    $SqlCmd.CommandTimeout = 600;

    $sql_tomove =read-file $script:INI_QUERY_TABLES2CLEAR
    $sqlTemplateDELETE = 'TRUNCATE TABLE {0} '

    do{
        $intermediate = invoke-sqlselectquery2 $SqlCmd $sql_tomove @{}
        Write-Output "Found $($intermediate.count) items"

        $intermediate.GetEnumerator() | ForEach-Object {
            $active = $_.value  
            $delete = $sqlTemplateDELETE   -f $active.oriname 
            Write-Debug "clear-database:: $delete"
            invoke-sqlselectquery0 $SqlCmd $delete | out-null 
        }
    }until($intermediate.count -eq 0)
}


## copy a database to another instance
## @src
## @dst
##
function copy-database([System.Data.SqlClient.SqlConnection]$read_Sqlconn, [System.Data.SqlClient.SqlConnection]$write_Sqlconn) {
    $read_SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $read_SqlCmd.Connection = $read_Sqlconn
    $write_SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $write_SqlCmd.Connection = $write_Sqlconn

    $sql_tomove =read-file $script:INI_QUERY_TABLES2COPY

    $sqlTemplateSELECT = 'SELECT x.*  FROM {0} x '
    $sqlTemplateDROP =  'IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N''{0}'') AND type in (N''U'')) DROP TABLE {0}'
    $sqlTemplateCREATE =  'SELECT x.* INTO {0} FROM (SELECT * FROM {1} WHERE 1=0 UNION ALL SELECT * FROM {1} WHERE 1=0) x' #union all should prevent identities to be duplicated.

    write-debug $sqlTemplateCREATE

    $intermediate = invoke-sqlselectquery2 $read_SqlCmd $sql_tomove @{}
    Write-Output "Found $($intermediate.count) items"

    $intermediate.GetEnumerator() | ForEach-Object {
        $active = $_.value  
        $from   = $sqlTemplateSELECT -f $active.oriname
        $to     = $active.destname
        $drop   = $sqlTemplateDROP   -f $active.destname 
        $create = $sqlTemplateCREATE -f $active.destname, $active.oriname 

        Write-Debug "copy-database:: $drop"
        Write-Debug "copy-database:: $from"
        Write-Debug "copy-database:: $to"
        Write-Debug "copy-database:: $create"

        invoke-sqlselectquery0 $write_SqlCmd $drop   | Out-Null 
        invoke-sqlselectquery0 $write_SqlCmd $create | Out-Null

        Copy-SqlTable $read_Sqlconn $write_SqlCnn $from $to

        $cnt1 = invoke-countTableRow $read_Sqlconn $active.oriname        
        $cnt2 = invoke-countTableRow $write_Sqlconn $active.destname 
        
        write-output "found $cnt1 records on $($active.oriname)"
        write-output "migrated $cnt2 records on $To"
        Write-Output  ''
    }
}



### copy tables from env to env 
function copy-SqlTable ( [System.Data.SqlClient.SqlConnection]$read_SqlCnn, [System.Data.SqlClient.SqlConnection]$write_SqlCnn, [string] $extract_sql, [string] $write_tableName, [int] $Batchsize = 100000){
Begin {
    $mywatch = [System.Diagnostics.Stopwatch]::StartNew()
    try{
        if ($read_SqlCnn.State -ne 'Open' ){
            $read_SqlCnn.Open()
        }
    } catch [System.Exception] {
        $_.Exception | Write-Error
        Write-Warning "can not open read connection"
        return
    }

    try{
        if ($write_SqlCnn.State -ne 'Open' ){
            $write_SqlCnn.Open()
        }
    } catch [System.Exception] {
        Write-Error $_.Exception 
        Write-Warning "can not open write connection"
        return
    }
}
Process {
      '{0:s}Z :: Copy-SqlTable() Connect to source...' -f [System.DateTime]::UtcNow | Write-Verbose
      "Source connection string: '$($read_SqlCnn.ConnectionString)'" | Write-Debug
      $sqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
      $sqlCmd.Connection  = $read_SqlCnn
      $sqlCmd.CommandText = $extract_sql
      $SqlReader = $sqlCmd.ExecuteReader()

      'Copy to target...' | Write-Verbose
      "Target connection string: '$($write_SqlCnn.ConnectionString)'" | Write-Debug

      try {
        $SqlBulkCopy = New-Object System.Data.SqlClient.SqlBulkCopy $write_SqlCnn  
        $SqlBulkCopy.EnableStreaming = $true
        $SqlBulkCopy.DestinationTableName = $write_tableName
        $SqlBulkCopy.BatchSize = $BatchSize
        $SqlBulkCopy.BulkCopyTimeout = 0 # seconds, 0 (zero) = no timeout limit
        $SqlBulkCopy.WriteToServer($SqlReader)

      }
      catch [System.Exception] {
        Write-Error $_.Exception
      }
      finally {
        'Copy complete. Closing...' | Write-Verbose
        $SqlReader.Close()
        $SqlBulkCopy.Close()
        $sqlCmd.Dispose()
      }
    }
End {
      $mywatch.Stop()
      '{0:s}Z Copy-SqlTable finished with success. Duration= {1}' -f [System.DateTime]::UtcNow,  $mywatch.Elapsed | Write-output
    }
} # Copy-SqlTable



function export-database([System.Data.SqlClient.SqlConnection]$SqlConnection, $sql_script,[string] $zipname = '' ) {
    $SqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $SqlCmd.Connection = $SqlConnection

    $sql = read-file $sql_script
    $sqlTemplate = read-file $script:INI_QUERY_SELECT

    $intermediate = invoke-sqlselectquery2 $SqlCmd $sql @{}
    Write-Output "Found $($intermediate.count) items"

    if ( [string]::IsNullOrEmpty($zipname) ){
        Write-Output "Dumped item will not be zipped "
        $do_zip=$false
    }else{
        Write-Output "Dumped item will be zipped "
        $zip_fqln = $script:INI_OUTPUT_DUMP_RAW -f $script:INI_OUTPUT_PATH,$zipname
        $zip_fqln = $zip_fqln + '.zip'
        $do_zip=$true
        backup-previousfile $zip_fqln 
    }

    $intermediate.GetEnumerator() | ForEach-Object {
        $active_table = $_.value
        $title="Dumping table {0} " -f $active_table.express
        $sql = $sqlTemplate -f $active_table.express
        $tmp = $active_table.DatabaseName+'-'+$active_table.SchemaName+'-'+$active_table.TableName
        $path = $script:INI_OUTPUT_DUMP_RAW -f $script:INI_OUTPUT_PATH,$tmp 
         ## todo
        invoke-onequeryreport $title $SqlConnection $sql @{}  $path

        #manage zip file immediatily
        if ( $do_zip ){
            move-tozip  $path $zip_fqln 
        }
        Start-Sleep -s $script:INI_WAIT_SECOND 
    }
}


function get-ConnectionStringFromXmlFile([string]$xml_config_path){
    try{
        #pas de xpath, on se contente de convertir le xml en object powershell et ensuite on parcours à la mano & en dur.
        [xml]$config_xml = read-file $xml_config_path
        $connection_string = $config_xml.connectionStrings.add.Attributes['connectionString'].value
    }catch{
        $Error = $_.Exception.Message 
        $msg="Can not retrieve connexion file and connection_string, giving up"
        Write-Warning $msg
        Write-Error $msg 
        Write-Error $Error 
        exit 1 
    }
    return $connection_string
}


function grant-CCM_Users( [System.Data.SqlClient.SqlConnection]$SqlConnection , [string[]]$employeeIDs , [int[]]$ccm_IDs , [string]$rolename, [int]$with_email ){
    Begin {
        #reduce risk of error
        $r = invoke-sqloneline $SqlConnection 'select count(*) from [e2sMaster].[dbo].[ccm_role] where role=@rolename ' @{'rolename'=$rolename}
        if ( $r -ne 1 ){
            throw "Can not find rolename $rolename"
        }
        
        #initialize 
        $SqlCmd1=New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd1.Connection=$SqlConnection
        $insert= @'
INSERT INTO [e2sMaster].[dbo].[ccm_user] ([fk_user],[fk_ccm],[fk_role],[email_send])
VALUES ( (SELECT [pk_user] FROM [e2sMaster].[dbo].[user] WHERE login=@login) , @ccm_id, (SELECT r.[pk_ccm_role]  FROM [e2sMaster].[dbo].[ccm_role] r where r.role=@rolename ), @email)
'@    
        $SqlCmd1.Parameters.AddWithValue('@login', 'foobar-login')
        $SqlCmd1.Parameters.AddWithValue('@ccm_id', 0)
        $SqlCmd1.Parameters.AddWithValue('@rolename', 'foobar-rolename')
        $SqlCmd1.Parameters.AddWithValue('@email', 0 )
        $SqlCmd1.CommandText = $insert 

    }#begin
    Process {
        $SqlCmd1.Parameters['@rolename'].Value  = $rolename 
        $SqlCmd1.Parameters['@email'].Value     = $with_email 

        foreach( $ccm in $ccm_IDs){
            $r = invoke-sqloneline $SqlConnection 'select count(*) from [e2sMaster].[dbo].[ccm] where [pk_ccm]=@ccm '  @{'ccm'=$ccm}
            if ( $r -ne 1 ){
                continue
            }
            $SqlCmd1.Parameters['@ccm_id'].Value = $ccm 
            foreach( $login in $employeeIDs ){
                $SqlCmd1.Parameters['@login'].Value  = $login
                try {
                    $res = $SqlCmd1.ExecuteNonQuery()
                    Write-Output "success: login $login + ccm $ccm + role $rolename + email $with_email"
                }catch{
                    $Error = $_.Exception.InnerException
                    Write-Debug $Error
                    Write-Warning "error: login $login + ccm $ccm + role $rolename + email $with_email"
                }
            }#foreach
        }#foreach
    }#process
    End{
        $SqlCmd1.Dispose()
    }#end
}



function grant-user_role( [System.Data.SqlClient.SqlConnection]$SqlConnection , [string[]]$employeeIDs , [string]$rolename ){
    Begin {
        #reduce risk of error
        $r = invoke-sqloneline $SqlConnection 'select count(*) from [e2sMaster].[dbo].[ccm_role] where role=@rolename ' @{'rolename'=$rolename}
        if ( $r -ne 1 ){
            throw "Can not find rolename $rolename"
        }
        
        #initialize 
        $SqlCmd1=New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd1.Connection=$SqlConnection
        $insert= @'
INSERT INTO [e2sMaster].[dbo].[ccm_user] ([fk_user],[fk_ccm],[fk_role],[email_send])
VALUES ( (SELECT [pk_user] FROM [e2sMaster].[dbo].[user] WHERE login=@login ), @ccm_id, (SELECT r.[pk_ccm_role]  FROM [e2sMaster].[dbo].[ccm_role] r where r.role=@rolename ), @email)
'@    
        $SqlCmd1.Parameters.AddWithValue('@login', 'foobar-login')
        $SqlCmd1.Parameters.AddWithValue('@ccm_id', 0)
        $SqlCmd1.Parameters.AddWithValue('@rolename', 'foobar-rolename')
        $SqlCmd1.Parameters.AddWithValue('@email', 0 )
        $SqlCmd1.CommandText = $insert 

    }#begin
    Process {
        $SqlCmd1.Parameters['@rolename'].Value  = $rolename 
        $SqlCmd1.Parameters['@email'].Value     = $with_email 
        foreach( $ccm in $ccm_IDs){
            $r = invoke-sqloneline $SqlConnection 'select count(*) from [e2sMaster].[dbo].[ccm] where [pk_ccm]=@ccm '  @{'ccm'=$ccm}
            if ( $r -ne 1 ){
                continue
            }
            $SqlCmd1.Parameters['@ccm_id'].Value = $ccm 
            foreach( $login in $employeeIDs ){
                $SqlCmd1.Parameters['@login'].Value  = $login
                try {
                    $res = $SqlCmd1.ExecuteNonQuery()
                    Write-Output "success: login $login + ccm $ccm + role $rolename + email $with_email"
                }catch{
                    $Error = $_.Exception.InnerException
                    Write-Debug $Error
                    Write-Warning "error: login $login + ccm $ccm + role $rolename + email $with_email"
                }
            }#foreach
        }#foreach
    }#process
    End{
        $SqlCmd1.Dispose()
    }#end
}


function invoke-countTableRow([System.Data.SqlClient.SqlConnection]$SqlConnection, [string]$tableName ){
    $sql = 'select count(*) cnt from {0} ' -f $tableName
    $res = invoke-sqloneline $SqlConnection $sql @{}
    return $res.cnt 
}


function invoke-sqloneline([System.Data.SqlClient.SqlConnection]$SqlConnection, [string]$sqlText, [hashtable]$param){
    $sqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
    $sqlCmd.Connection = $SqlConnection
    $res = invoke-sqlselectquery4 $sqlCmd $sqlText $param 
    $sqlCmd.Dispose()
    return $res[0]
}


function invoke-onequeryreport([string]$title, [System.Data.SqlClient.SqlConnection]$SqlConnection, [string]$sqlText, [hashtable]$sqlparameters, [string]$path){
    Write-Output $title 
  
    $sqlCmd = New-Object System.Data.SqlClient.SqlCommand
    $sqlCmd.Connection = $sqlConnection
    $sqlCmd.CommandText = $sqlText
   
    foreach ($h in $sqlparameters.GetEnumerator()) {
        $SqlCmd.parameters.AddWithValue( "@"+$h.Name, $h.value) | out-null 
    }

    $SqlReader =  $SqlCmd.ExecuteReader()
    #$columns_name = receive-sqlColumnName $SqlReader 
    try{
        $data = Receive-SqlData $SqlReader
        write-datatabletocsv $data $path 
    }
    catch{
        $Error = $_.Exception.Message
        Write-Error $Error
        Write-Warning -Verbose "Error executing SQL on database [$Database] on server [$SqlServer]. Statement: `r`n$SqlStatement"
    }
}


function invoke-sqlselectquery0 ([System.Data.SqlClient.SqlCommand]$SqlCmd, [string]$sqlText ){
     return invoke-sqlselectquery4 $SqlCmd $sqlText @{} 
}



function invoke-sqlselectquery2( [System.Data.SqlClient.SqlCommand]$SqlCmd, [string]$sqlText , [hashtable]$sqlparameters ){
    foreach ($h in $sqlparameters.GetEnumerator()) {
        $SqlCmd.parameters.AddWithValue( "@"+$h.Name, $h.value) | out-null 
    }
    if ( [String]::IsNullOrEmpty($sqlText) -eq $false ){
        $SqlCmd.CommandText = $sqlText
    }

    $SqlReader =  $SqlCmd.ExecuteReader()
    return    Receive-SqlData_HashtableByRow $SqlReader
 }


function invoke-sqlselectquery3( [System.Data.SqlClient.SqlCommand]$SqlCmd, [string]$sqlText , [hashtable]$sqlparameters ){
    foreach ($h in $sqlparameters.GetEnumerator()) {
        $SqlCmd.parameters.AddWithValue( "@"+$h.Name, $h.value) | out-null 
    }
    if ( [String]::IsNullOrEmpty($sqlText) -eq $false ){
        $SqlCmd.CommandText = $sqlText
    }

    $SqlReader =  $SqlCmd.ExecuteReader()
    return receive-SqlData_HashtableByCol $SqlReader
}


function invoke-sqlselectquery4( [System.Data.SqlClient.SqlCommand]$SqlCmd, [string]$sqlText , [hashtable]$sqlparameters ){
    foreach ($h in $sqlparameters.GetEnumerator()) {
        $SqlCmd.parameters.AddWithValue( "@"+$h.Name, $h.value) | out-null 
    }
    if ( [String]::IsNullOrEmpty($sqlText) -eq $false ){
        $SqlCmd.CommandText = $sqlText
    }

    $SqlReader =  $SqlCmd.ExecuteReader()
    return receive-SqlData  $SqlReader
}


function invoke-sqlselectquery5 ([System.Data.SqlClient.SqlCommand]$SqlCmd, [string]$sqlText, [hashtable]$sqlparameters ){
     foreach ($h in $sqlparameters.GetEnumerator()) {
        $SqlCmd.parameters.AddWithValue( "@"+$h.Name, $h.value) | out-null 
    }
    if ( [String]::IsNullOrEmpty($sqlText) -eq $false ){
        $SqlCmd.CommandText = $sqlText
    }
    $affectedRow = $SqlCmd.ExecuteNonQuery() 
    return $affectedRow 
}


function move-tozip ([string] $path ,[string] $zip_fqln ){
    if ( Test-Path -Path $zip_fqln -PathType leaf )  {
        Write-Output "Add $path to $zip_fqln"
        Compress-Archive -Path $path -DestinationPath $zip_fqln -Update -CompressionLevel $script:INI_COMPRESSION_LEVEL
    }else{
        Write-Output "Create $path to $zip_fqln"
        Compress-Archive -Path $path  -DestinationPath $zip_fqln -CompressionLevel  $script:INI_COMPRESSION_LEVEL
    }
    Remove-Item -LiteralPath $path -Recurse 
}


function open-sqlconnexion(  [Parameter(ValueFromPipeline)][string]  $connection_string ){

    $SqlConnection = New-Object System.Data.SqlClient.SqlConnection
    try{
        $SqlConnection.ConnectionString = $connection_string 
        $SqlConnection.Open();
    }catch{
        $Error = $_.Exception.Message 
        $msg="Can not open the database connection, giving up"
        Write-Warning $msg
        Write-Error $Error 
        exit 1
    }
    return $SqlConnection 
}


function read-file ([string] $filename) {
    if ( [System.IO.Path]::IsPathRooted($filename) ){
         return Get-Content  $filename 
    }
    else{
        return Get-Content (join-path  $script:INI_ROOT  $filename )
       
    }
}


#[SqlDataReader] 
function Receive-SqlData([System.Data.Common.DbDataReader]  $cursor ){
    $Datatable = New-Object System.Data.DataTable
    $Datatable.Load($cursor)
    $SqlReader.Dispose()
    return $Datatable
}



#[SqlDataReader]
function receive-SqlData_HashtableByRow([System.Data.Common.DbDataReader]  $cursor ){
    $result= @{}
    $columns_name = receive-sqlColumnName $cursor 
    $line=0
    while( $cursor.Read() ){
        $row = New-object psobject 
        foreach($col in $columns_name){
            add-member -InputObject $row -MemberType NoteProperty -Name $col -Value $cursor[$col]|out-null 
        }
        $result.add($line,$row)|out-null
        $line++
    }#while
    $cursor.Dispose()
    return $result
}


#[SqlDataReader]
function receive-SqlData_HashtableByCol([System.Data.Common.DbDataReader] $cursor){
    $result=@{}
    for($i=0;$i -lt $cursor.VisibleFieldCount;$i++){
        $columns_vals = New-Object Collections.Generic.List[string]
        $result.add($cursor.GetName($i),$columns_vals)|out-null 
    }
    $line=0

    while( $cursor.Read() ){
        foreach($col in $result.keys ){
            $result[$col].add($cursor[$col]) |out-null 
        }
    }#while
    $cursor.Dispose()
    return $result
}


function receive-sqlColumnName([System.Data.Common.DbDataReader] $cursor){
    $columns_name = New-Object Collections.Generic.List[string]
    for($i=0;$i -lt $cursor.VisibleFieldCount;$i++){
        $columns_name.add($cursor.GetName($i) ) | out-null 
    }
    return $columns_name
}



function sync-userbyidentity{
[CmdletBinding()]
Param(
    [Parameter(ValueFromPipeline )][AllowEmptyString()][Microsoft.ActiveDirectory.Management.ADAccount[]] $members, 
    [System.Data.SqlClient.SqlConnection]$SqlConnection ,
    [int] $defaultProfilID, 
    [int] $defaultRoleID
) 
    Begin{
        $SqlCmd1=New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd1.Connection=$SqlConnection
        $update = 'UPDATE [e2sMaster].[dbo].[user] set is_active = 1 where login = @login'
        $insert_u = @'
INSERT INTO [e2sMaster].[dbo].[user] ([login],[fk_profile],[last_name],[first_name],[email],[date_creation],[is_active],[fk_language])
VALUES (@login,@fk_profile,@lastname,@firstname,@email,GETDATE(),1,'EN')
'@
        $insert_r = @'
INSERT INTO [e2sMaster].[dbo].[user_role] ([fk_user],[fk_role])
VALUES ((SELECT [pk_user] FROM [e2sMaster].[dbo].[user] WHERE login=@login) , @role )
'@
    }
    Process{
        foreach( $identity in $members){
            Write-Output  "working on $($identity.employeeID)"     
            $res = invoke-sqlselectquery5 $SqlCmd1 $update  @{'login'=$identity.employeeID } 
            $SqlCmd1.Parameters.RemoveAt(0)
            if ( $res -eq 0 ){
                $SqlCmd2=New-Object -TypeName System.Data.SqlClient.SqlCommand
                $SqlCmd2.Connection=$SqlConnection
                $res = invoke-sqlselectquery5 $SqlCmd2 $insert_u  @{
                    'login'=$identity.employeeID;
                    'lastname'=$identity.surname;
                    'firstname'=$identity.givenname;
                    'email'=$identity.mail;
                    'fk_profile'=$defaultProfilID 
                    }
                $SqlCmd3=New-Object -TypeName System.Data.SqlClient.SqlCommand
                $SqlCmd3.Connection=$SqlConnection
                $res = invoke-sqlselectquery5 $SqlCmd2 $insert_r  @{
                    'login'=$identity.employeeID;
                    'role'=$defaultRoleID
                    }
                Write-Output "$res added"
                $SqlCmd2.Dispose()
                $SqlCmd3.Dispose()
            }else {
                Write-Output "$res active"
            }
        }#foreach

    }#Process

    End{
        $SqlCmd1.Dispose()
    }#End 
}#sync-userbyidentity



function write-hastabletocsv ([hashtable] $t, $file ){
    backup-previousfile $file
    if ( $t -eq $null -or $t.Count -eq 0 ){
        Write-Information 'empty result set'
        "" | Out-File $file -Encoding default
    }
    else {
        $t[0] | ConvertTo-Csv -NoTypeInformation -Delimiter $script:INI_DELIMITER |  Select-Object -First 1 | Out-File $file -Encoding default 
        $t.GetEnumerator() | ForEach-Object {
            $_.Value | ConvertTo-Csv -NoTypeInformation -Delimiter $script:INI_DELIMITER   | Select-Object -Skip 1    | Out-File -Append $file -Encoding default 
        }
    }
}


function write-datatabletocsv( $t , [string]$file ){
    backup-previousfile $file
    $cnt = ( $t | Measure-Object ).Count
    if ( $cnt -gt 0 ){
        $t | Export-Csv -Delimiter $script:INI_DELIMITER  -NoTypeInformation -Path $file 
    }else{
        Write-Information 'empty result set'
        "" | Out-File $file -Encoding default
    }
}


