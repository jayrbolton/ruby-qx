
# ruby-qx

Ruby Postgresql interface and query expression builder. This allows you to directly write Sql expressions in ruby without any obfuscation or obscuring of the SQL syntax and semantics. You can easily write complex joins, subqueries, etc without wrestling with an ORM.

For now this is tied to the `pg` gem, but this could be abstracted out in the future (open a PR!)

# config

```rb

require 'qx'

Qx.config({ database_url: "postgres://username:password@domain/db_name" })

```

# .execute

# SELECT FROM


```rb
Qx.select('col_name1', 'col_name2').from('table_name')
# SELECT col_name1, col_name2 FROM table_name

Qx.select(['col_name1', 'col_name2']).from('table_name')
# SELECT col_name1, col_name2 FROM table_name

Qx.select('table_name.col_name1', 'table_name.col_name2'].from('table_name')
# SELECT table_name.col_name1, table_name.col_name2 FROM table_name
```

## WHERE

```rb
expr = Qx.select('col_name').from('table_name')

expr.where('col_name = 123')
# SELECT col_name FROM table_name WHERE col_name = 123

# Interpolation with a hash
expr.where('col_name = $val', val: 123)
# SELECT col_name FROM table_name WHERE col_name = 123

# WHERE x AND y
expr.where('x=1').andWhere('y=2') 
# SELECT col_name FROM table_name WHERE x = 1 AND y = 2

# Array interpolation
expr.where("col_name IN ($arr)", [1,2,3])
# SELECT col_name FROM table_name WHERE col_name IN (1, 2, 3)

# Any postgres expression can go in the string
expr.where("x = 1 OR y = 2")
# SELECT col_name FROM table_name WHERE x = 1 OR y = 2
```

## JOINs

### INNER JOIN

```rb

.append("JOIN ($subq) AS xyz ON xyz.id=123")

expr = Qx.select('table_name.col1', 'joined_table1.col', 'joined_table2.col').from(:table_name)
  .join(
    ['joined_table1', 'joined_table1.col = table_name.col']
  , ['joined_table2', 'joined_table2.col = $id', {id: 123]
  )
# SELECT table_name.col1, joined_table1.col, joined_table2.col FROM table_name
#   JOIN joined_table1 ON joined_table1.col = table_name.col
#   JOIN joined_table2 ON joined_table2.col = 123
```

### LEFT OUTER JOIN

```rb
expr = Qx.select('table_name.col1', 'joined_table1.col', 'joined_table2.col').from(:table_name)
  .left_join(
    ['joined_table1', 'joined_table1.col = table_name.col']
  , ['joined_table2', 'joined_table2.col = $id', {id: 123]
  )
# SELECT table_name.col1, joined_table1.col, joined_table2.col FROM table_name
#   LEFT JOIN joined_table1 ON joined_table1.col = table_name.col
#   LEFT JOIN joined_table2 ON joined_table2.col = 123
```

## HAVING / ORDER BY / GROUP BY / LIMIT / OFFSET

```rb
expr = Qx.select('col1').from('table_name')
  .order_by('created_at DESC')
  .group_by('status')
  .having('COUNT(joined_table.id) < 10')
  .limit(10)
  .offset(10)
# SELECT col1 FROM table_name
#   ORDER BY created_at DESC
#   GROUP BY status
#   HAVING COUNT(joined_table.id) < 10
#   LIMIT 10
#   OFFSET 10
```

## subqueries

# INSERT

## RETURNING

# UPDATE

# DELETE FROM

# utils

## pretty-print

## .page_offset


