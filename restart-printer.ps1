# Définir le filtre pour sélectionner uniquement les fichiers PDF
$openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
$openFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
$openFileDialog.Filter = "PDF files (*.pdf)|*.pdf"
$openFileDialog.Multiselect = $true
$openFileDialog.Title = "Sélectionnez les fichiers PDF à imprimer"
$acrobatPath = "C:\Program Files (x86)\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe"
$printername='FOLLOW_YOU'
$printerDriver='RICOH PCL6 UniversalDriver V4.32'
$printerPort='127.0.0.1' 
$printername='Pro 8200_8100 EB-34 PCL 6'

# Afficher la fenêtre de sélection de fichiers
$result = $openFileDialog.ShowDialog()

if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
    # Récupérer la liste des fichiers sélectionnés
    $files = $openFileDialog.FileNames
    
foreach ($file in $files) {
  try{
      $finfo = Get-Item $file 
      Set-Location $finfo.DirectoryName 
      #direct print 
      #$arg = '/t "{0}" "{1}" "{2}" "{3}" ' -f $finfo.Name, $printername, $printerDriver, $printerPort
      $arg = @('/p', $finfo.name)
      $proc = Start-Process -FilePath $acrobatPath -ArgumentList $arg  -Wait -NoNewWindow -PassThru
      Stop-Process -Id $proc.Id -ErrorAction Ignore
  }
  catch {
    Write-Warning "can not print $file"
  }
}
}

# Nettoyage
Remove-Variable -Name openFileDialog
