
# ruby-qx

A simple SQL expression string constructor in ruby. Do you want to directly write efficient SQL expressions in Ruby, safely using data from Ruby-land, without wrestling with a bloated ORM? Then this is the lib for you.

This is implements a subset of the SQL language that I find most useful. Add new SQL clauses with a PR if you'd like to see more in here.

Currently, it supports execution with postgresql using the `pg` gem. If you'd like to include MySql or another db for built-in execution, please make a PR. Or you can pass the generated SQL string into your engine with `MyDB.execute(qx_query.parse)`.

# Qx.config(options)

`Qx.config` only takes an argument hash and currently only supports one key: `database_url`. Include the full database URL, including protocol, username, pass, domain, and database name.

```rb
require 'qx'

Qx.config(database_url: "postgres://username:password@domain/db_name")
```

`.config` is best called once when your app is starting up (eg Rails initializer).

# Qx.execute(sql, options), expr.execute(sql, options)

You can execute any SQL string or object using `.execute` or `#execute`.

```rb
Qx.execute("SELECT x FROM y WHERE x = $n", n: 1)
expr = Qx.select(:x).from(:y).where("x = $n", n: 1)
expr.execute(verbose: true)
Qx.execute(expr, format: 'csv')
```

`.execute` takes an optional options hash as its second argument, which can have:

* verbose: defaults to false. Will print the query string if true.
* format: defaults to 'hash'. If set to 'hash', returns hashes. If set to 'csv', returns a CSV-style array of arrays (see below).

### hash format

By default, `.execute` has the format of `'hash'`. This means it returns an array of hashes, where each hash has its keys set to your selected column names and values set to the result values.

If the result only contains a single hash, then it will return just that single hash without being within an array.

If the result is empty, it returns `nil`.

### csv format

If you set `format: 'csv'` in your execution options, you will get back a CSV-style array of rows.

The first row will be the headers -- ie. all of the column names you selected on.

All the subsequent arrays will be the rows values for every result.

CSV format is useful for exports or for saving memory in large selects.

# SELECT FROM: Qx.select(col1, col2, ...).from(table_name)

```rb
Qx.select(:col_name1, :col_name2).from('table_name')
# SELECT "col_name1", "col_name2" FROM "table_name"

Qx.select('table_name.col_name1', 'table_name.col_name2'].from(:table_name)
# SELECT "table_name"."col_name1", "table_name"."col_name2" FROM "table_name"
```

## WHERE: expr.where("sql_expr", data_to_interpolate)

```rb
expr = Qx.select('col_name').from('table_name')

expr.where('col_name = 123')
# SELECT col_name FROM table_name WHERE (col_name = 123)

# Interpolation with a hash
expr.where('col_name = $val', val: 123)
# SELECT col_name FROM table_name WHERE (col_name = 123)

# Conditional with hash shortcut (similar to rails)
expr.where(col_name: 123)
# SELECT col_name FROM table_name WHERE (col_name = 123)
expr.where(col_name: [123, 456])
# SELECT col_name FROM table_name WHERE (col_name IN (123, 456))
```

#### WHERE x AND y: expr.where(x, data_to_interpolate).and_where(y, data_to_interpolate)

You can use `and_where` to chain together conditions using `AND`.

```rb
expr.where('x=1 OR y=2').and_where('z=4') 
# SELECT col_name FROM table_name WHERE (x=1 OR y=2) AND (z=4)
```

## JOINs

### INNER JOIN

Use `.join` for an inner join. Pass in many arrays, where each array has the
format `[table_to_join, condition_to_join_on, data_to_interpolate]`. The third
piece, `data_to_interpolate`, can be left out if you dont need it.


```rb

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

Similarly, left outer joins can be achieved with `.left_join`

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

Many other SELECT clauses can be used as expected:

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

You can use subqueries in any FROM, JOIN, WHERE, etc. Simply pass in another Qx expression object.

You need to use `expr.as(name)` to alias your subquery

```rb
subq = Qx.select('table_id', "STRING_AGG(name, ' ')").from("assoc").group_by('table_id').as(:assoc)
Qx.select('id', 'assoc.name').from('table')
  .join([subq, 'assoc.table_id=table.id'])
# SELECT id, assoc.name FROM table
#   JOIN (
#     SELECT table_id, STRING_AGG(name, ' ')
#     FROM assoc
#     GROUP BY table_id
#   ) AS assoc
#     ON assoc.table_id=table.id
```

You can similarly embed subqueries in a WHERE or a FROM.

# INSERT INTO x VALUES y



## RETURNING

# UPDATE

# DELETE FROM

## shortcut / helper functions

Some convenience functions are provided that compose some of SQL expressions.

#### Qx.fetch(table_name, ids_or_data)

This is a quick way to fetch some full rows of data by id or another column.

You can either pass in an array of ids, a single id, or a hash that matches on columns.

```rb
Qx.fetch(:table_name, [12, 34, 56])
# SELECT * FROM table_name WHERE ids IN (12, 34, 56)

donation = Qx.fetch(:donations, 23)
# SELECT * FROM donations WHERE ID IN (23)
donor = Qx.fetch(:donors, donation['supporter_id'])
# SELECT * FROM donors WHERE ID IN (33)

donation = Qx.fetch(:donations, {status: 'active'})
# SELECT * FROM donations WHERE status IN ('active')
```

# utils

## Performance Optimization Tools

TODO. Since this lib is built with Postgresql, it takes advantage of its performance optimization tools such as EXPLAIN, ANALYZE, and statistics queries.

### EXPLAIN: expr.explain

For performance optimization, you can use an `EXPLAIN` command on a Qx select expression object.

See here: http://www.postgresql.org/docs/8.3/static/using-explain.html

```rb
Qx.select(:id)
  .from(:table)
  .where("id IN ($ids)", ids: [1,2,3,4]) 
  .explain
# TODO
```


## expr.pp (pretty-printing)

This gives a nicely formatted and colorized output of your expression for debugging.

```rb
Qx.select(:id)
  .from(:table)
  .where("id IN ($ids)", ids: [1,2,3,4]) 
  .pp
```

## expr.paginate(current_page, page_length)

This is a convenience method for more easily paginating a SELECT query using the combination of OFFSET and LIMIT

Simply pass in the page length and the current page to get the paginated results.

```rb
Qx.select(:id).from(:table).paginate(2, 30)
# SELECT id FROM table OFFSET 30 LIMIT 30
```

