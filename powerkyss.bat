@echo Running: %0
@set SCRIPTPATH=%~pd0
@set POWERSHELL=%SystemRoot%\system32\WindowsPowerShell\v1.0\powershell.exe
@CD /D %SCRIPTPATH%"


%POWERSHELL% -file "%SCRIPTPATH%\powerkyss.ps1"  -environnement METIER -extract_all  -report_tag 'PERSO' 
