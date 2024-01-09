
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



Class ScriptUser{
    [string] $username 
    [securestring] $secure_password
    hidden [boolean] $passwordValid    #was chalenge against infrastructure
    hidden [boolean] $passwordAsked    #was provided by user
    hidden [boolean] $passwordInited   #was successfully provided to the object, password not challenged
    [boolean] $do_store_password
    [boolean] $do_ask_password 
    [string]  $password_store 
    static [string] $store_extention = $script:INI_PASSWORD_DISK_EXT

    
    ScriptUser ([string]$username, [string]$working_directory, [boolean]$store_password, [boolean]$ask_password) {
        $this.username =$username
        $this.do_ask_password =   $ask_password
        $this.do_store_password = $store_password
        $this.password_store = [System.IO.Path]::Combine( $working_directory , $username + [ScriptUser]::store_extention ) 
        $this.passwordValid = $false  
        $this.passwordAsked = $false
        $this.passwordInited= $false 
    } #constructor 


    <#
    allow for lazy init of password.
    #>
    hidden [void] initPassword() {
        if ( $this.passwordInited ){
            return 
        }
        # main purpose is to use the store
        $this.readPasswordStore() 

        #fallback method is to prompt.
        if ( $this.passwordInited  ){
            Write-Host "using store's password"
        }
        else {
            $this.promptPassword() 
        }

        #if it wasn't successfull,let's cry
        if ( -not( $this.passwordInited )){
            Write-Warning "No valid password found"
            throw "No password available"
        }
    }


    [void] promptPassword(){ 
        if ( $this.do_ask_password ){
            $text="Please enter password for user "+$this.username 
            try{
                $this.secure_password = Read-Host -assecurestring   $text
                $this.secure_password.MakeReadOnly()
                $this.passwordInited = $true 
                $this.passwordAsked = $true 
            }catch {
                $myError = $_.Exception.Message
                 Write-Warning  "can not use stored password"
                 Write-Error $myError 
            }
        }
    }


    [void] readPasswordStore(){
        if ((test-path $this.password_store ) -and $this.do_store_password ){
            try {
                $this.secure_password = Get-Content $this.password_store | ConvertTo-SecureString 
                $this.secure_password.MakeReadOnly()
                $this.passwordInited = $true
            }
            catch {
                $myError = $_.Exception.Message
                Write-Warning  "can not use stored password"
                Write-Error $myError 
            }
        }

    }


    [securestring] getPassword(){
        $this.initPassword()
        return $this.secure_password
    }


    [string] getPasswordClearText(){
        Write-Warning 'using cleartext password :( '
        $this.initPassword()
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.secure_password))
    }


    [Object] getCredential(){
        $this.initPassword()
        $cred = New-Object System.Management.Automation.PSCredential ($this.username, $this.secure_password ) 
        return $cred        
    }

    
    [void] updateStore(){
        if ($this.do_store_password ){
            if ( $this.passwordValid ){
                if ( $this.passwordAsked ){
                    $this.secure_password | ConvertFrom-SecureString | Out-File $this.password_store
                        Write-Verbose "new password saved"
                } else {
                        Write-Verbose "nothing to do"
                }
            }else {
                #enfin on dégomme le mot de passe stocké s'il n'a pas marché.
                if (-not ($this.passwordAsked) -and (Test-Path $this.password_store) ){
                    if ( $script:INI_RENAME_INVALID_STORE) {
                        $tmp = Get-Item $this.password_store 
                        $tgt = [IO.Path]::Combine( $tmp.DirectoryName, $tmp.BaseName, $script:INI_INVALIDPWD_DISK_EXT )
                        Move-Item -Path $this.password_store -Destination $tgt -Verbose    
                    }
                    else{
                        Remove-Item -Path $this.password_store -Verbose
                    }
                }
            }
        }#if do_pass_store
    }

    
    [void] Dispose(){
        $this.updateStore()
    }


    [void] confirmPassword(){
        if ( $this.passwordInited ){
            $this.passwordValid = $true 
        }
        else {
            Write-Warning 'password was never provided nor read from store'
            throw exception 'Shall not confirm inited password'
        }
    }

    [void] denyPassword(){
        if ( $this.passwordInited ){
            $this.passwordValid = $false 
        }
        else {
            Write-Warning 'password was never provided nor read from store'
            throw exception 'Shall not confirm inited password'
        }
    } 

} #class

function new-ScriptUser([string]$username, [boolean]$store_password,[boolean]$ask_password, [string]$working_directory){
    return [ScriptUser]::new($username, $store_password, $ask_password, $working_directory)
}

function get-ScriptUser_Credential([ScriptUser]$su){
    return $su.getCredential()
}

function confirm-ScriptUser_Password([ScriptUser]$su){
    return $su.confirmPassword()
}

function deny-ScriptUser_Password([ScriptUser]$su){
    return $su.denyPassword()
}

function update-ScriptUser_Store([ScriptUser]$su){
    return $su.updateStore()
}


#https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_classes 

# Define the types to export with type accelerators.
$script:ExportableTypes  =@(
    [ScriptUser]
)
# Get the internal TypeAccelerators class to use its static methods.
$script:TypeAcceleratorsClass = [psobject].Assembly.GetType(
    'System.Management.Automation.TypeAccelerators'
)
# Ensure none of the types would clobber an existing type accelerator.
# If a type accelerator with the same name exists, throw an exception.
$script:ExistingTypeAccelerators = $script:TypeAcceleratorsClass::Get
foreach ($Type in $script:ExportableTypes) {
    if ($Type.FullName -in $script:ExistingTypeAccelerators.Keys) {
        $Message = @(
            "Unable to register type accelerator '$($Type.FullName)'"
            'Accelerator already exists.'
        ) -join ' - '

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
    foreach($Type in $script:ExportableTypes) {
        $script:TypeAcceleratorsClass::Remove($Type.FullName)
    }
}.GetNewClosure()
