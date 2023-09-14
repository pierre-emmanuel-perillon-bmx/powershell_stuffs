<#
As of now, you can also use ports 465 and 587 to establish a secure connection to the relays. 
 Port 465 (fully encrypted TLS connection) is highly recommended and should be used whenever possible (if your SMTP client supports it). 
 Port 587 (StartTLS) is less secure as TLS negotiation may result in an unencrypted connection being established to transmit the email.
 Port 25 (unsecure) is still available for clients that support neither TLS nor StartTLS.
  
https://learn.microsoft.com/en-us/dotnet/api/system.net.mail.smtpclient.enablessl?view=net-7.0 
 The SmtpClient class only supports the SMTP Service Extension for Secure SMTP over Transport Layer Security as defined in RFC 3207. 
 In this mode, the SMTP session begins on an unencrypted channel, then a STARTTLS command is issued by the client to the server to 
 switch to secure communication using SSL. See RFC 3207 published by the Internet Engineering Task Force (IETF) for more information.

 An alternate connection method is where an SSL session is established up front before any protocol commands are sent. This connection 
 method is sometimes called SMTP/SSL, SMTP over SSL, or SMTPS and by default uses port 465. This alternate connection method using SSL 
 is not currently supported.
#>

$smtp =  @{
    'username' = "noreply@biomerieux.com"
    'password' = ""
    'server' = 'smtp.biomerieux.net' 
    'port'   = 587  
}

$bodyTemplate = @"
hello!
This is a test email send to {5} by {0} from {1} on {2}.
options:
 SMTP_ACCOUNT: {6}
 SMTP_SERVER : {3}
 SMTP_PORT   : {4}

 BR
"@

function Compose-TestEmail( [string]$recipient, [string]$attachmentfile ) {
    $currentDate = (Get-Date -Format "dddd yyyy/MM/dd HH:mm:ss K")
    $message = new-object Net.Mail.MailMessage;
    $message.From = $config_smtp.username 
    $message.To.Add($recipient);
    $message.Subject = "Test SMTP at {0}" -f $currentDate;
    $message.Body = $bodyTemplate -f $env:USERNAME, $env:COMPUTERNAME, $currentDate,$smtp.server,$smtp.port,$recipient,$smtp.username ;

    if ( [string]::IsNullOrEmpty($attachmentfile ) -or -not( Test-Path -Path $attachmentfile)  ){
        Write-Output "No attachment to the email."
    }
    else{
        $attachment = New-Object Net.Mail.Attachment($attachmentfile);
        $message.Attachments.Add($attachment);
    }
    return $message
  }

function Send-ToEmail([Net.Mail.MailMessage] $message){
    $client = new-object Net.Mail.SmtpClient($smtp.server, $smtp.port );
    $client.EnableSSL = $smtp.port -eq 587  #25 or 587 are supported
    $client.Credentials = New-Object System.Net.NetworkCredential($smtp.username, $smtp.password );
    $client.send($message);
    $client
    Write-Output "Mail Sent" ;
 }


$email = Compose-TestEmail -recipient 'jerikojerk on github :)' -attachmentfile 'index.png' 

Send-ToEmail  -message $email 
