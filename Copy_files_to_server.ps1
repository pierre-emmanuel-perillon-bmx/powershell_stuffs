
$RUNTIME_ROOT = [System.IO.Path]::GetDirectoryName($MyInvocation.MyCommand.Path)
$INI_WRITE_COMPUTER = 'my_windows_server.domain' 
$INI_USERNAME = 'my_login'


$INI_LIST = (
    'file1.txt',
    'file2.txt',
    'file3.txt')

$TARGET_PATH = 'C:\Users\user\Desktop\directory'
$SOURCE_PATH = $RUNTIME_ROOT
import-module "$RUNTIME_ROOT\Class_ScriptUser.psm1" -Force


function copy-files-toremote( [array]$list_files, [string]$read_dir, [string]$write_dir, [System.Management.Automation.Runspaces.PSSession] $remote  ) {
    $it = 0
    ForEach ( $file in $list_files ) {
        if ( $remote.State -ne 'Opened' ) {
            break
        }
        $read = [System.IO.Path]::Combine($read_dir, $file )
        try {
            Copy-Item -Path $read -ToSession $remote -Destination $write_dir -Verbose 
            $it++
        }
        catch {
            $myError = $_.Exception.Message
            Write-Warning "can not copy file $read to $write_dir"
            Write-Error $myError 
        }
    }
    Write-Output "$it files copied, $($list_files.Count) expected"
}

function copy-files-toLocal( [array]$list_files, [string]$read_dir, [string]$write_dir, [System.Management.Automation.Runspaces.PSSession] $remote  ) {
    $it = 0
    ForEach ( $file in $list_files ) {
        if ( $remote.State -ne 'Opened' ) {
            break
        }
        $read = [System.IO.Path]::Combine($read_dir, $file )
        try {
            Copy-Item -Path $read -FromSession $remote -Destination $write_dir -Verbose -
            $it++
        }
        catch {
            $myError = $_.Exception.Message
            Write-Warning "can not copy file $read to $write_dir"
            Write-Error $myError 
        }
    }
    Write-Output "$it files copied, $($list_files.Count) expected"
}



$user = New-Object ScriptUser ( $INI_USERNAME, $true, $true, $RUNTIME_ROOT )
$cred = $user.getCredential()
$remote = New-PSSession -ComputerName $INI_WRITE_COMPUTER -Credential $cred  # -UseSSL
if ( $remote.State -eq 'Opened' ) {
    $user.confirmPassword()
    $user.updateStore()
}

$title = "move files between local and distant=$INI_WRITE_COMPUTER" 
$question = 'Which awy ?'
$choices = 'local ==>> &DISTANT', '&LOCAL <<== distant', '&Cancel'

$decision = $Host.UI.PromptForChoice($title, $question, $choices, 2)

switch ( $decision ) {
    0 {
        Write-output 'local ==>> DISTANT'
        copy-files-toremote $INI_LIST $SOURCE_PATH $TARGET_PATH $remote 
    }
    1 {
        Write-output 'LOCAL <<== distant'
        copy-files-toLocal $INI_LIST $TARGET_PATH $SOURCE_PATH $remote 
    }
    2 {
        Write-output "Cancel"
    }
}


