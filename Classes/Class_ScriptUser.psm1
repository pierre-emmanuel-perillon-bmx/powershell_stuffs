$script:INI_PASSWORD_DISK_EXT = '.secret'
$script:INI_INVALIDPWD_DISK_EXT = '.invalid-secret'
$script:INI_RENAME_INVALID_STORE = $true 

function script:Checkpoint-columnname( [Parameter(ValueFromPipeline = $true)][string] $c ){
    Begin{
        $reg=[regex]::new(']|\[|''|"|`|@|\.')
    } 
    Process{
        $reg.Replace( $c.trim(' ][''"`').ToLowerInvariant(),'')
    }
}

Class UsersHabilitation {
    [string[]]$employeeIDs
    [Microsoft.ActiveDirectory.Management.ADAccount[]] $identities
    [System.Data.SqlClient.SqlConnection]$SqlConnection

    UsersHabilitation ([System.Data.SqlClient.SqlConnection]$SqlConnection, [Microsoft.ActiveDirectory.Management.ADAccount[]] $accounts  ) {
        $this.identities=$accounts 
        $this.employeeIDs=$accounts | Select-Object -ExpandProperty employeeid 
        $this.SqlConnection = $SqlConnection
    }

<#
    UsersHabilitation ([System.Data.SqlClient.SqlConnection]$SqlConnection, [string[]]$employeeIDs ) {
        $this.employeeIDs = $employeeIDs
        $this.identities = @()
        $this.SqlConnection = $SqlConnection
    }
#>

    hidden [void] initquery_CCM([System.Data.SqlClient.SqlCommand]$SqlCmd_I) {
        $sql_insert = @'
INSERT INTO [e2sMaster].[dbo].[ccm_user] ([fk_user],[fk_ccm],[fk_role],[email_send])
VALUES ( (SELECT [pk_user] FROM [e2sMaster].[dbo].[user] WHERE login=@login) , @ccm_id, (SELECT r.[pk_ccm_role]  FROM [e2sMaster].[dbo].[ccm_role] r where r.role=@rolename ), @email)
'@
        $SqlCmd_I.Connection = $this.SqlConnection    
        $SqlCmd_I.Parameters.Add('@login',    [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.Parameters.Add('@ccm_id',   [Data.SQLDBType]::BigInt )       | Out-Null
        $SqlCmd_I.Parameters.Add('@rolename', [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.Parameters.Add('@email',    [Data.SQLDBType]::Bit)           | Out-Null
        $SqlCmd_I.CommandText = $sql_insert 
        $SqlCmd_I.Prepare()
    }


    hidden [void] initquery_usersprofiles( [System.Data.SqlClient.SqlCommand]$SqlCmd_U) {
        $sql_update = @'
UPDATE [e2sMaster].[dbo].[user] 
SET [fk_profile]=(SELECT [pk_profile] FROM [e2sMaster].[dbo].[profile] WHERE [code]=@profil_code)
WHERE login=@login
'@  
        $SqlCmd_U.Connection = $this.SqlConnection
        $SqlCmd_U.Parameters.Add('@login',       [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_U.Parameters.Add('@profil_code', [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_U.CommandText = $sql_update
        $SqlCmd_U.Prepare()   
    }

    hidden [void] initquery_usersroles( [System.Data.SqlClient.SqlCommand]$SqlCmd_I, [System.Data.SqlClient.SqlCommand] $SqlCmd_D) {
        #initialize
        $sql_insert = @'
INSERT INTO [e2sMaster].[dbo].[user_role] ([fk_user],[fk_role])
VALUES ( (SELECT [pk_user] FROM [e2sMaster].[dbo].[user] WHERE login=@login), (SELECT r.[pk_role]  FROM [e2sMaster].[ref].[role] r where r.[name]=@rolename))
'@      
        $SqlCmd_I.Connection = $this.SqlConnection
        $SqlCmd_I.Parameters.Add('@login',    [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.Parameters.Add('@rolename', [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.CommandText = $sql_insert 
        $SqlCmd_I.Prepare()

        $sql_delete = @'
DELETE [e2sMaster].[dbo].[user_role] 
FROM [e2sMaster].[dbo].[user_role] ur inner join [e2sMaster].[dbo].[user] u on u.[pk_user]=ur.[fk_user]
WHERE u.[login]=@login 
'@
        $SqlCmd_D.Connection = $this.SqlConnection
        $SqlCmd_D.Parameters.Add('@login', [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_D.CommandText = $sql_delete
        $SqlCmd_D.Prepare()

    }

    hidden [void] initquery_createUsers ( [System.Data.SqlClient.SqlCommand]$SqlCmd_I, [System.Data.SqlClient.SqlCommand]$SqlCmd_U) {
        $update = @'
UPDATE [e2sMaster].[dbo].[user] set is_active = 1 where login = @login
'@
        $SqlCmd_U.Connection = $this.SqlConnection
        $SqlCmd_U.Parameters.Add('@login', [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_U.CommandText = $update 
        $SqlCmd_U.Prepare()
    
        $insert = @'
INSERT INTO [e2sMaster].[dbo].[user] ([login],[fk_profile],[last_name],[first_name],[email],[date_creation],[is_active],[fk_language])
VALUES (@login,(SELECT pk_profile FROM [e2sMaster].[dbo].[profile] WHERE code=@profilCode),@lastname,@firstname,@email,GETDATE(),1,'EN')
'@
        $SqlCmd_I.Connection = $this.SqlConnection
        $SqlCmd_I.Parameters.Add('@login',      [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.Parameters.Add('@lastname',   [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.Parameters.Add('@firstname',  [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.Parameters.Add('@email',      [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.Parameters.Add('@profilCode', [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_I.CommandText = $insert 
        $SqlCmd_I.Prepare()

    }

    #=====================
    [void] grant_CCMs( [int[]]$ccm_IDs , [string]$ccm_rolename, [int]$with_email , [boolean] $deleteFirstByUser, [boolean]$deleteFirstByCCM ) {
        #reduce risk of error
        $r = invoke-sqloneline $this.SqlConnection ( new-sqlQueryOptions'select count(*) from [e2sMaster].[dbo].[ccm_role] where role=@rolename ' @{'rolename' = $ccm_rolename } )
        if ( $r -ne 1 ) {
            throw "Can not find rolename $ccm_rolename"
        }

        $sql_select_ByCCM =  'SELECT count(*) FROM [e2sMaster].[dbo].[ccm] WHERE [pk_ccm]=@ccm '
        $sql_delete_ByUser = 'DELETE [e2sMaster].[dbo].[ccm_user] FROM [e2sMaster].[dbo].[ccm_user] cr inner join [e2sMaster].[dbo].[user] u on u.[pk_user]=cr.fk_user WHERE cr.[login]=@login'
        $sql_delete_ByCCM =  'DELETE [e2sMaster].[dbo].[ccm_user] FROM [e2sMaster].[dbo].[ccm_user] WHERE [fk_ccm]=@ccm_id'

        $SqlCmd_I = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $this.initquery_CCM($SqlCmd_I)
        $SqlCmd_I.Parameters['@rolename'].Value = $ccm_rolename 
        $SqlCmd_I.Parameters['@email'].Value = $with_email 

        $opt_select = new-sqlQueryOptions $sql_select_ByCCM
        $opt_delete = new-sqlQueryOptions $sql_delete_ByCCM
        $opt_delete_byUser = new-sqlQueryOptions $sql_delete_ByUser
        foreach ( $ccm in $ccm_IDs) {
            $opt_select.param = @{'ccm' = $ccm }
            $r = invoke-sqloneline $this.SqlConnection $opt_select
            if ( $r -ne 1 ) {
                Write-Output "skipping CCM ID $ccm that does not exists "
                continue
            }
            if ( $deleteFirstByCCM ) {
                $opt_delete.param = @{'ccm' = $ccm }
                $r = invoke-sqloneline $this.SqlConnection $opt_delete
                Write-Output "deleted $r rows for CCM ID $ccm "
            }

            $SqlCmd_I.Parameters['@ccm_id'].Value = $ccm 
            foreach ( $login in $this.employeeIDs ) {
                $SqlCmd_I.Parameters['@login'].Value = $login
                if ( $deleteFirstByUser ) {
                    $opt_delete_byUser.param = @{'login' = $login }
                    $r = invoke-sqloneline $this.SqlConnection $opt_delete_byUser
                    Write-Output "remove $r records for user $login"
                }
                try {
                    $res = $SqlCmd_I.ExecuteNonQuery()
                    if ( $res -eq 1 ) {
                        Write-Output "success: login $login + ccm $ccm + role $ccm_rolename + email $with_email"
                    }
                    else {
                        Write-warning "failed: login $login + ccm $ccm + role $ccm_rolename + email $with_email"
                    }
                }
                catch {
                    $ExceptionMsg = $_.Exception.InnerException
                    Write-Debug $ExceptionMsg
                    Write-Warning "error: login $login + ccm $ccm + role $ccm_rolename + email $with_email"
                }
            }#foreach
        }#foreach

        $SqlCmd_I.Dispose()
    }
    

    #=====================
    [void] grant_users_roles( [string[]]$app_rolenames , [boolean] $deleteFirst ) {
        #reduce risk of error
        $opt = new-sqlQueryOptions 'select count(*) cnt from [e2sMaster].[ref].[role] r where r.name=@rolename ' 
        Foreach ( $rolename in $app_rolenames ) {
            $opt.param = @{'rolename' = $rolename }
            $r = invoke-sqloneline $this.SqlConnection $opt 
            if ( $r.cnt -ne 1 ) {
                throw "Can not find rolename $rolename"
            }
        }#foreach

        $SqlCmd_I = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd_D = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $this.initquery_usersroles($SqlCmd_I, $SqlCmd_D)

        foreach ( $login in $this.employeeIDs ) {
            if ( $deleteFirst ) {
                $SqlCmd_D.Parameters['@login'].Value = $login
                $res = $SqlCmd_D.ExecuteNonQuery()
                Write-Output "Users roles: removed $res roles"
            }
            Foreach ( $rolename in $app_rolenames ) { 
                $SqlCmd_I.Parameters['@login'].Value = $login
                $SqlCmd_I.Parameters['@rolename'].Value = $rolename 

                try {
                    $res = $SqlCmd_I.ExecuteNonQuery()
                    Write-Output "success: login $login + role $rolename "
                }
                catch {
                    $ExceptionMsg = $_.Exception.InnerException
                    Write-Debug $ExceptionMsg
                    Write-Warning "error: login $login + role $rolename "
                }
<#
dead code.
        $sql_update = @'
UPDATE [e2sMaster].[dbo].[user_role] 
SET [fk_user]=(SELECT [pk_user] FROM [e2sMaster].[dbo].[user] WHERE [login]=@login)
,[fk_role]=(SELECT [pk_role]  FROM [e2sMaster].[ref].[role] where [name]=@rolename)
'@
        $SqlCmd_U.Connection = $this.SqlConnection
        $SqlCmd_U.Parameters.Add('@login',    [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_U.Parameters.Add('@rolename', [Data.SQLDBType]::NVarChar, 100) | Out-Null
        $SqlCmd_U.CommandText = $sql_update
        $SqlCmd_U.Prepare()


                $SqlCmd_U.Parameters['@login'].Value = $login
                $SqlCmd_U.Parameters['@rolename'].Value = $rolename 
                try {
                    $res = $SqlCmd_U.ExecuteNonQuery()
                    if ( $res -gt 0 ) {
                        Write-Output "success: login $login + role $rolename"
                    }
                }
                catch {
                    $ExceptionMsg = $_.Exception.InnerException
                    Write-Debug $ExceptionMsg
                    Write-Warning "error: login $login + role $rolename "
                }
#>
            }#foreach
        }#foreach
        $SqlCmd_I.Dispose()
        $SqlCmd_D.Dispose()
    }

    #=====================
    [void] grant_users_profile( [string]$ProfileCode ) {
        #reduce risk of error
        $opt = new-sqlQueryOptions 'SELECT count(*) cnt FROM [e2sMaster].[dbo].[profile] WHERE code =@profilCode' @{'profilCode' = $ProfileCode }
        $tmp = invoke-sqloneline $this.SqlConnection $opt
        if ( $tmp.cnt -eq 0 ) {
            throw "Can not find ProfilID $ProfileCode"
        }
    
        $SqlCmd_U = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $this.initquery_usersprofiles($SqlCmd_U)
        $SqlCmd_U.Parameters['@profil_code'].Value = $ProfileCode 

        foreach ( $login in $this.employeeIDs ) {
            $SqlCmd_U.Parameters['@login'].Value = $login
            try {
                $res = $SqlCmd_U.ExecuteNonQuery()
                if ( $res -gt 0 ) {
                    Write-Output "success: login $login + profilCode $ProfileCode"
                }
            }
            catch {
                $ExceptionMsg = $_.Exception.InnerException
                Write-Debug $ExceptionMsg
                Write-Warning "error: login $login + profilCode $ProfileCode "
            }
        }#foreach

        $SqlCmd_U.Dispose()

    }


    #=====================
    [void] sync_user_disable_all(  [string]$exception_user ) {
        $SqlCmd = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd.Connection = $this.SqlConnection
        $opt = new-sqlQueryOptions  'UPDATE [e2sMaster].[dbo].[user] set is_active = 0 where login <> @login and is_active = 1' @{'login' = $exception_user }
        $res = invoke-sqlselectquery5 $SqlCmd $opt
        Write-Output "$res active users have been disablesd"
        $SqlCmd.Dispose()
    }

    #=====================
    [void] add_users( [string] $defaultProfilCode ) { 
        if ( $this.identities.Count -eq 0 ) {
            throw 'identities were not provided'
        }
        $opt = new-sqlQueryOptions 'SELECT count(*) cnt FROM [e2sMaster].[dbo].[profile] WHERE code =@profilCode' @{'profilCode' = $defaultProfilCode }
        $tmp = invoke-sqloneline $this.SqlConnection $opt
        if ( $tmp.cnt -eq 0 ) {
            throw "Can not find ProfilID $defaultProfilCode"
        }

        $SqlCmd_U = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $SqlCmd_I = New-Object -TypeName System.Data.SqlClient.SqlCommand
        $this.initquery_createUsers($SqlCmd_I, $SqlCmd_U)

        foreach ( $identity in $this.identities) {
            Write-Output  "working on $($identity.employeeID)"   
            $SqlCmd_U.Parameters[0].Value = $identity.employeeID 
            $res = $SqlCmd_U.ExecuteNonQuery()
            if ( $res -eq 0 ) {
                $SqlCmd_I.Parameters['@login'].Value = $identity.employeeID
                $SqlCmd_I.Parameters['@lastname'].Value = $identity.surname
                $SqlCmd_I.Parameters['@firstname'].Value = $identity.givenname
                $SqlCmd_I.Parameters['@email'].Value = $identity.mail
                $SqlCmd_I.Parameters['@profilCode'].Value = $defaultProfilCode 
                $res = $SqlCmd_I.ExecuteNonQuery()
                Write-Output "added $($identity.employeeID)  ($res)"

            }
            else {
                Write-Output "$res active"
            }
        }#foreach
        $SqlCmd_U.Dispose()
        $SqlCmd_I.Dispose()
    }



} # class 


Function new-UsersHabilitation( [System.Data.SqlClient.SqlConnection]$SqlConnection, [Microsoft.ActiveDirectory.Management.ADAccount[]] $identities ){
    return [UsersHabilitation]::new( $SqlConnection,  $identities  )
}

Function grant-UsersHabilitation_CCMs([usersHabilitations] $uh, [int[]]$ccm_IDs , [string]$ccm_rolename, [int]$with_email , [boolean] $deleteFirstByUser, [boolean]$deleteFirstByCCM ){
    return $uh.grant_CCMs($ccm_IDs, $ccm_rolename, $with_email , $deleteFirstByUser, $deleteFirstByCCM )
}


Function grant-UsersHabilitation_users_roles([usersHabilitations] $uh, [string[]]$app_rolenames , [boolean] $deleteFirst ){
    return $uh.grant_users_roles($app_rolenames , $deleteFirst)
}

Function grant-UsersHabilitation_users_profile([usersHabilitations] $uh, [string]$ProfileCode ){
    return $uh.grant_users_profile($ProfileCode)
}

function sync_user_disable_all($exception_user){
    return [UsersHabilitation]::sync_user_disable_all($exception_user)
}

function add-UsersHabilitation([usersHabilitations] $uh, [int] $defaultProfilCode){
    return $uh.add_users($defaultProfilCode)
}





#https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes 

# Define the types to export with type accelerators.
$script:ExportableTypes = @(
    [UsersHabilitation]
)
# Get the internal TypeAccelerators class to use its static methods.
$script:TypeAcceleratorsClass = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')

# Ensure none of the types would clobber an existing type accelerator.
# If a type accelerator with the same name exists, throw an exception.
$script:ExistingTypeAccelerators = $script:TypeAcceleratorsClass::Get
foreach ($Type in $script:ExportableTypes) {
    if ($Type.FullName -in $script:ExistingTypeAccelerators.Keys) {
        $Message = "Unable to register type accelerator '$($Type.FullName)' - Accelerator already exists."

        throw [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new($Message),
            'TypeAcceleratorAlreadyExists',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $Type.FullName
        )
    }
}
# Add type accelerators for every exportable type.
foreach ($Type in $script:ExportableTypes) {
    $script:TypeAcceleratorsClass::Add($Type.FullName, $Type)
}
# Remove type accelerators when the module is removed.
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    foreach ($Type in $script:ExportableTypes) {
        $script:TypeAcceleratorsClass::Remove($Type.FullName)
    }
}.GetNewClosure()
