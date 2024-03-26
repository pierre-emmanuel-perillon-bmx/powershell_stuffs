$INI_GROUPAD = 'MY_AD_GROUP'
$INI_ROLENAME = 'MY_IAM_GROUP'
$INI_IAM_EXTRACT  ='.\user_roles.csv'
$INI_IAM_CACHE  = '.\user_cached.csv'
$INI_CSVHEADERS = 'IAM Code;User Type;First Name;Last Name;Full Name;Email Address;Employee Status;Functional Location;Country;rolename;roletype;Company;role description'
$INI_Upkeep_log ='.\membership-{0}.log' -f (get-date -format yyyMMddHHmmss)

#list users by email
$add ='


'


#list users by email
$remove = '

'

$user_add = $add.trim() -split '\s+'  | % { $_.trim() } 
$user_rem = $remove.trim() -split '\s+'  | % { $_.trim() } 

Start-Transcript $INI_Upkeep_log 

function Update-FileToCache {
    param(
        [string] $SourcePath,
        [string] $DestinationPath,
        [string] $RoleName
    )

    # Check if the source file is newer than the destination file
    $sourceLastWriteTime = (Get-Item $SourcePath).LastWriteTime
    if ( (Test-Path $DestinationPath) -and (Get-Item $DestinationPath).LastWriteTime -ge (Get-Item $SourcePath).LastWriteTime) {
        Write-Output "The cache file is up-to-date: $DestinationPath"
    } else {
            
            
            $reader = [System.IO.StreamReader]::new($SourcePath)
            $writer = [System.IO.StreamWriter]::new($DestinationPath)

            # Write the header line
            $writer.WriteLine($INI_CSVHEADERS)

            $lineMajorCount = 0 
            $lineMinorCount = 0
            $matchesCount = 0

            $timer = [System.Diagnostics.Stopwatch]::StartNew()

            while (!$reader.EndOfStream) {
                $line = $reader.ReadLine()
                $lineMinorCount++

                if ($line.Contains($RoleName)) {
                    $writer.WriteLine($line)
                    $matchesCount++

                    # Flush the buffer every 96 matches
                    if ($matchesCount % 16 -eq 0) {
                        $writer.Flush()
                    }
                }

                if ($lineMinorCount -gt 4096 ) {
                    $lineMajorCount += $lineMinorCount
                    $lineMinorCount = 0  
                    $elapsedSeconds = $timer.Elapsed.TotalSeconds
                    $readPerformance = [math]::Round( $lineMajorCount / $elapsedSeconds, 2)
                    Write-Host "Processed $lineMajorCount lines, $matchesCount matches ($readPerformance lines/sec)"
                }#if progress
            }#while $reader

            # Close the streams
            $reader.Close()
            $writer.Close()

            Write-Host "Cache file updated: $DestinationPath"
        }
}#function


function read-Cache ($DestinationPath) {
    # Si aucune modification n'est effectuée dans le cache, ouvrir le fichier de destination pour peupler $filteredData
    try {
        $filteredData = Import-Csv -Path $DestinationPath -Delimiter ';'
        Write-Information "Données lues à partir du cache : $DestinationPath"
    }
    catch {
        Write-Warning "Impossible de lire le fichier en cache : $_"
    }

    $hashTable = @{}
    foreach ($entry in $filteredData) {
        $id = $entry.'IAM Code'
        $roles = $entry.'rolename'

        if ($id -and $roles) {
            if ($hashTable.ContainsKey($id)) {
                $hashTable[$id] += $roles |Out-Null
            } else {
                $hashTable.add($id , @($roles) ) |Out-Null
            }
        } else {
            Write-Warning "Entry does not contain valid 'IAM Code' or 'rolename'. Skipping."
        }
    }

    return $hashTable
}


function search-habilitation {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline = $true)]
        [array] $users,
        [string] $groupname,
        [boolean] $expect,
        [hashtable] $IAM, 
        [boolean] $mode_read
    )

    begin {
        $groupMembers = @{}
        $members = Get-ADGroupMember -Identity $groupname
        foreach ($member in $members) {
            $groupMembers[$member.ObjectGUID] = $true
        }
    }

    process {
        foreach ($x in $users) { 
            $email = "$x".ToLower()
            if ([string]::IsNullOrWhiteSpace($email)) {
                continue
            }
            $u = Get-ADUser -Filter { EmailAddress -like $email } -Properties EmployeeID,EmailAddress

            if ($u -eq $null) {
                Write-Warning "??? - ??? - $email - ??? - ??? - not matched "
                continue 
            }

            $sam =   $u.Name
            $id =    $u.EmployeeID 
            $fname = $u.GivenName
            $lname = $u.Surname
            

            if ( $IAM.ContainsKey($id) ){
                $biorole  = ' with IAM role '
            }
            else {
                $biorole =' not in IAM '
            }

            $found = $groupMembers.ContainsKey($u.ObjectGUID)

            if ($found) {
                $msg_AD = 'found in AD'
            }
            else {
                $msg_AD = 'not found in AD'
            }

           
            if ($found -ne $expect) {
                $tmp ="WARN $id - $email - $fname - $lname".PadRight(72)
            } else {
                $tmp ="PASS $id - $email - $fname - $lname".PadRight(72)  
            }

            Write-Output "$tmp $biorole : $msg_AD"
        }
    }

    end {
        # Code exécuté à la fin du traitement des éléments (si nécessaire)
    }
} #function


function Show-MultipleColumns {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Array,
        [int]$ColumnCount = 3
    )
    $res = @() 
    
    for ($i = 0; $i -lt $Array.Count; $i++) {
        $row = $Array[$i]

        for ($j = 1; $j -lt $ColumnCount ; $j++) {
            $a = $i+$j 
            $row = $row.padRight(38*$j)
            if ( $a -ge $Array.count ){
                break 
            }
            $row = $row + "  " + $Array[$a]
        }
        Write-Output $row
        $i = $a
    }
    Write-Output ""

}



Write-Output "--- hellow world ---"

update-FileToCache $INI_IAM_EXTRACT $INI_IAM_CACHE $INI_ROLENAME
$rolesHtb = read-Cache  $INI_IAM_CACHE

Write-Output "--- cache is ready ---"
Write-Output "reference group is  $INI_GROUPAD"
Write-Output "reference role  is  $INI_ROLENAME"
Write-Output "users to add: "
Show-MultipleColumns $user_add 3

Write-Output "users to remove:"
Show-MultipleColumns $user_rem 3

Write-Output "users in common:"
$user_delta = $user_rem | ?{$_ -iin $user_add }
Show-MultipleColumns $user_delta 3


Write-Output "---added users---"
search-habilitation $user_add $INI_GROUPAD $true  $rolesHtb

Write-Output "---removed users---"
search-habilitation $user_rem $INI_GROUPAD $false  $rolesHtb


Stop-Transcript 


