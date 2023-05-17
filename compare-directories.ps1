$src="E:\some\where\over\rainbow" 
$dst="D:\backups\some\where\over\rainbow" 

$fsoRef = Get-ChildItem -Recurse -path $src 
$fsoDif = Get-ChildItem -Recurse -path $dst

$totalsize = 0
$totalfile = 0
Compare-Object -ReferenceObject $fsoRef -DifferenceObject $fsoDif | ForEach-Object {

   $SideIndicator=if ( $_.SideIndicator  -eq "<=" ) { "missing" } else {"extra"}
   $InputObject =$_.InputObject
   $Path = $_.InputObject.fullname.toString().replace("$src","#")
   $size=if ( $InputObject.PSIsContainer ) { 0 } else { $InputObject.length } 
   $totalfile = $totalfile +1
   $totalsize = $totalsize + $size 

   Write-Output "[$sideIndicator] $Path $size"
}

Write-output ""
Write-output "SUMMARY - delta: $totalfile files for $totalsize octets" 
