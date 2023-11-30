SELECT
 SCHEMA_NAME(sysTab.SCHEMA_ID) as SchemaName,
 sysTab.NAME AS TableName, 
 parti.rows AS RowCounts,
 SUM(alloUni.total_pages) * 8 AS TotalSpaceKB,
 SUM(alloUni.used_pages) * 8 AS UsedSpaceKB,
 (SUM(alloUni.total_pages) - SUM(alloUni.used_pages)) * 8 AS UnusedSpaceKB
FROM sys.tables sysTab
INNER JOIN sys.indexes ind ON sysTab.OBJECT_ID = ind.OBJECT_ID and ind.Index_ID<=1
INNER JOIN sys.partitions parti ON ind.OBJECT_ID = parti.OBJECT_ID AND ind.index_id = parti.index_id
INNER JOIN sys.allocation_units alloUni ON parti.partition_id = alloUni.container_id
WHERE sysTab.is_ms_shipped = 0 AND ind.OBJECT_ID > 255 AND parti.rows>0
GROUP BY sysTab.Name, parti.Rows,sysTab.SCHEMA_ID
Order BY schemaname, parti.rows desc