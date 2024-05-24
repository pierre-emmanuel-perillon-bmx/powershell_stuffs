select s.name "schema_name", t.name "table_name", i.name "index_name", i.type, i.is_disabled,i.fill_factor,i.is_primary_key,
ius.user_lookups,
ius.user_scans,
ius.user_seeks,
ius.user_updates,
ius.user_lookups+ius.user_seeks+ius.user_lookups "user_read",
( select max(v) from (values (ius.last_user_lookup),(ius.last_user_scan),(ius.last_user_seek)) as value(v) ) as "last_time_user",
ius.system_lookups,
ius.system_scans,
ius.system_updates,
ius.system_seeks,
ius.system_lookups+ius.system_scans+ius.system_seeks "system_read",
( select max(v) from (values (ius.last_system_lookup),(ius.last_system_scan),(ius.last_system_seek)) as value(v) ) as "last_time_system"  
FROM   
       sys.objects AS o 
       inner JOIN sys.schemas AS s 
          ON o.schema_id = s.schema_id 
       inner JOIN sys.indexes AS i 
          ON o.object_id = i.object_id 
	   inner JOIN sys.tables as t 
	      on o.object_id =  t.object_id 
	   LEFT JOIN  sys.dm_db_index_usage_stats AS ius 
	      on ( ius.index_id=i.index_id and o.object_id = ius.object_id )
where o.type = 'U' and i.type=2
and  i.is_disabled= 0 
order by 1,2,user_read desc