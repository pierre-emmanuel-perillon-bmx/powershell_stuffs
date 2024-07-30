Param(
[Parameter()]
    [ValidateSet('NAME','CONTENT','OLD')]
    [string[]]
    $action

 )



# Set the directory to search
$directory = "F:"

# Function to find backup files
function Find-BackupFiles {
    param (
        [string]$path
    )
    # Define backup file extensions or patterns
    $backupExtensions = @(".bak", ".backup", ".bkp", ".old", ".tmp")
    # Get all files in the directory with backup extensions
    $backupFiles = Get-ChildItem -Path $path -Recurse -File | Where-Object {
        $backupExtensions -contains $_.Extension
    }
    return $backupFiles
}

# Function to find duplicated files
# Function to find duplicated files
function Find-DuplicatedFiles {
    param (
        [string]$path
    )
    # Get all files in the directory
    $files = Get-ChildItem -Path $path -Recurse -File
    Write-Information "FS parsed"
    # Group files by their size
    $sizeGroups = $files | Group-Object -Property Length
    Write-Information "FS grouped" 
    # Initialize an empty array for duplicated files
    $duplicatedFiles = [System.Collections.ArrayList]::new()

    # For each size group with more than one file, compute the hash and group by hash
    foreach ($group in $sizeGroups) {
        if ($group.Count -gt 1) {
            $hashGroups = $group.Group | Group-Object {
                Get-FileHash $_.FullName | Select-Object -ExpandProperty Hash
            }
            # Add groups with more than one file to the duplicated files array
            foreach ( $subgroup in $hashGroups ){
                if ( $subgroup.count  -gt 1 ){
                    $duplicatedFiles.AddRange( $subgroup.group ) | Out-Null 
                    Write-Information "found duplicate"
                    Write-Information $subgroup 
                }
            }

        }
    }

    return $duplicatedFiles
}

# Function to find files with the same name in different folders
function Find-FilesWithSameNameDifferentFolders {
    param (
        [string]$path
    )
    # Get all files in the directory
    $files = Get-ChildItem -Path $path -Recurse -File

    # Group files by their name
    $nameGroups = $files | Group-Object -Property Name

    # Select groups that have more than one file (same name)
    $sameNameFiles = $nameGroups | Where-Object { $_.Count -gt 1 }

    return $sameNameFiles
}

# Run the functions and display the results

if ( $action -eq 'OLD' ){
Write-Output "Backup Files:"
$backupFiles = Find-BackupFiles -path $directory
$backupFiles | ForEach-Object { $_.FullName }

}

if ( $action -eq 'CONTENT' ){
Write-Output "`nDuplicated Files:"
$duplicatedFiles = Find-DuplicatedFiles -path $directory
$duplicatedFiles | ForEach-Object {
    $_.Group | ForEach-Object { $_.FullName }
    Write-Output ""
}

}

if ( $action -eq 'NAME' ){
$sameNameFiles = Find-FilesWithSameNameDifferentFolders -path $directoryz
Write-Output "`nFiles with Same Name in Different Folders:"
$sameNameFiles | ForEach-Object {
    $_.Group | ForEach-Object { $_.FullName }
    Write-Output ""
}


}