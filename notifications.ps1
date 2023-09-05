

$config = New-Object -TypeName psobject 
Add-Member -InputObject $config -MemberType NoteProperty -Name time_begin_human  -Value '16:55:00' 
Add-Member -InputObject $config -MemberType NoteProperty -Name time_end_human    -Value '17:10:00'

Add-Type -AssemblyName System.Windows.Forms

Function Invoke-BalloonTip {
    <#
    .Synopsis
        Display a balloon tip message in the system tray.
    .Description
        This function displays a user-defined message as a balloon popup in the system tray. This function
        requires Windows Vista or later.
    .Parameter Message
        The message text you want to display.  Recommended to keep it short and simple.
    .Parameter Title
        The title for the message balloon.
    .Parameter MessageType
        The type of message. This value determines what type of icon to display. Valid values are
    .Parameter SysTrayIcon
        The path to a file that you will use as the system tray icon. Default is the PowerShell ISE icon.
    .Parameter Duration
        The number of seconds to display the balloon popup. The default is 1000.
    .Inputs
        None
    .Outputs
        None
    .Notes
         NAME:      Invoke-BalloonTip
         VERSION:   1.0
         AUTHOR:    Boe Prox
    #>

    [CmdletBinding()]
    Param (
        [Parameter(Mandatory=$True,HelpMessage="The message text to display. Keep it short and simple.")]
        [string]$Message,

        [Parameter(HelpMessage="The message title")]
         [string]$Title="Attention $env:username",

        [Parameter(HelpMessage="The message type: Info,Error,Warning,None")]
        [System.Windows.Forms.ToolTipIcon]$MessageType="Info",

        [Parameter(HelpMessage="The number of milliseconds to display the message.")]
        [int]$Duration=1000,   
         
        [Parameter(HelpMessage="The path to a file to use its icon in the system tray")]
        [string]$SysTrayIconPath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'    


    )



    try {
        $global:balloon| out-null 

        if (-NOT $global:balloon) {
            $global:balloon = New-Object System.Windows.Forms.NotifyIcon

            #Mouse double click on icon to dispose
            [void](Register-ObjectEvent -InputObject $balloon -EventName MouseDoubleClick -SourceIdentifier IconClicked -Action {
            #Perform cleanup actions on balloon tip
            #Write-Verbose ‘Disposing of balloon’
            $global:balloon.dispose()
            Unregister-Event -SourceIdentifier IconClicked
            Remove-Job -Name IconClicked
            Remove-Variable -Name balloon -Scope Global
            })
        }
    }
    catch{
        $global:balloon = New-Object System.Windows.Forms.NotifyIcon

        #Mouse double click on icon to dispose
        [void](Register-ObjectEvent -InputObject $balloon -EventName MouseDoubleClick -SourceIdentifier IconClicked -Action {
            #Perform cleanup actions on balloon tip
            #Write-Verbose 'Disposing of balloon'
            $global:balloon.dispose()
            Unregister-Event -SourceIdentifier IconClicked
            Remove-Job -Name IconClicked
            Remove-Variable -Name balloon -Scope Global
        })
    }

    #Need an icon for the tray
    #$path = Get-Process -id $pid | Select-Object -ExpandProperty Path

    #Extract the icon from the file
    $balloon.Icon = [System.Drawing.Icon]::ExtractAssociatedIcon($SysTrayIconPath)

    #Can only use certain TipIcons: [System.Windows.Forms.ToolTipIcon] | Get-Member -Static -Type Property
    $balloon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]$MessageType
    $balloon.BalloonTipText  = $Message
    $balloon.BalloonTipTitle = $Title
    $balloon.Visible = $true

    #Display the tip and specify in milliseconds on how long balloon will stay visible
    $global:balloon.ShowBalloonTip($Duration)

    Write-Verbose "Ending function"

}

$tmp_d = ( Get-date -Format 'yyyy/M/d' ).Split("/") 
$tmp_h = $config.time_begin_human.split(":")

$tbegin =  Get-Date -Year $tmp_d[0]  -Month $tmp_d[1] -Day $tmp_d[2]  -Hour $tmp_h[0] -Minute $tmp_h[1]  -UFormat "%s"     
$tbegin = [double]::Parse($tbegin)

$tmp_h = $config.time_end_human.split(":")
$tend =  Get-Date -Year $tmp_d[0]  -Month $tmp_d[1] -Day $tmp_d[2]  -Hour $tmp_h[0] -Minute $tmp_h[1] -UFormat "%s"
$tend = [double]::Parse($tend) 

$tnow = Get-Date  -UFormat "%s"
$tnow = [double]::parse($tnow)


$tmiddle = ($tend - $tbegin)/2


###Info,Error,Warning$level = None,None

if ( $tnow -lt $tbegin ){
    $level = 'None' 
    $message = "Il est {0} !"
    $title = "C'est pas encore l'heure"
}
elseif (  $tnow -lt $tmiddle ){
    $level = 'Info' 
    $message = "Il est {0}, il faut se préparer!"
    $title = "C'est l'heure de la nounou"
}
elseif ( $tnow -lt $tend ){
    $level = 'Warning'
    $message = "Il est {0}, il faut y aller !"
    $title = "C'est l'heure de la nounou"
}
else {
    $level = 'Error'
    $message = "Il est {0}, il faut y aller rapidement !"
    $title = "C'est l'heure de la nounou"
}



$message = $message -f ( get-date -Format "HH:mm" )

Invoke-BalloonTip -Message $message -Title $title -Duration 5000 -MessageType $level 

return 0
