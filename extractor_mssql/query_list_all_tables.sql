USE [ipmanager]
SELECT
 SCHEMA_NAME(sysTab.SCHEMA_ID) as SchemaName,
 sysTab.NAME AS TableName,
 db_name() as DatabaseName,
 '['+ db_name()+'].['+SCHEMA_NAME(sysTab.SCHEMA_ID)+'].['+sysTab.NAME+']' as express
FROM sys.tables sysTab
WHERE systab.type = 'U' and sysTab.NAME not in (NULL)
order by 1,2