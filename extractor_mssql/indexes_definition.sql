SELECT 
 s.name [schema name] 
      ,TBL.[name] AS [Table Name]
      ,INX.[name] AS [Index Name]
      ,DS1.[IndexColumnsNames]
      ,DS2.[IncludedColumnsNames]
FROM [sys].[indexes] INX
INNER JOIN [sys].[tables] TBL
    ON INX.[object_id] = TBL.[object_id]
inner join [sys].schemas s on  s.schema_id = tbl.schema_id 
CROSS APPLY 
(
    SELECT STUFF
    (
        (
            SELECT ' [' + CLS.[name] + ']'
            FROM [sys].[index_columns] INXCLS
            INNER JOIN [sys].[columns] CLS 
                ON INXCLS.[object_id] = CLS.[object_id] 
                AND INXCLS.[column_id] = CLS.[column_id]
            WHERE INX.[object_id] = INXCLS.[object_id] 
                AND INX.[index_id] = INXCLS.[index_id]
                AND INXCLS.[is_included_column] = 0
			order by INXCLS.key_ordinal ASC
            FOR XML PATH('')
        )
        ,1
        ,1
        ,''
    ) 
) DS1 ([IndexColumnsNames])
CROSS APPLY 
(
    SELECT STUFF
    (
        (
            SELECT ' [' + CLS.[name] + ']'
            FROM [sys].[index_columns] INXCLS
            INNER JOIN [sys].[columns] CLS 
                ON INXCLS.[object_id] = CLS.[object_id] 
                AND INXCLS.[column_id] = CLS.[column_id]
            WHERE INX.[object_id] = INXCLS.[object_id] 
                AND INX.[index_id] = INXCLS.[index_id]
                AND INXCLS.[is_included_column] = 1
			order by INXCLS.key_ordinal ASC
            FOR XML PATH('')
        )
        ,1
        ,1
        ,''
    ) 
) DS2 ([IncludedColumnsNames])
where INX.type=2
order by 1,2,3
