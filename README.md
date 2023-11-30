# powershell_stuffs
this repository is here to share scripts i can publish.

## test-domain.ps1 
it is a basic tool to perform kind of curl request (powershell fashion) on a list of domain to get the status.

## compare_directories.ps1
it is basic script to check if 2 folders are in sync. maybe we should test what happend if files are not same size.

## powerkyss.ps1
allow user to interact with a vault to create a listing of saved credential. it comes with .readme & .bat to simplify its use.


##extractor_mssql
allow someone to generate CSV from database connection.
- verify output folder exists CSV will be generated here.
- customise config.xml
- customise file query_list_all_tables.sql to select only intesting tables, it may work with views but not tested.
- if target csv file already exists it may 
Script may not be suited for larges tables are everything is put in memory.
