
# ruby-qx

A simple SQL expression string constructor in ruby. It allows you to directly and safely write efficient SQL expressions in Ruby, using data from Ruby-land, without wrestling with an ORM.

This implements a subset of the SQL language that we find most useful so far. Add new SQL clauses with a PR if you'd like to see more in here.

This library uses ActiveRecord for executing SQL, taking advantage of its connection pooling features.

# Qx.config(options)

`Qx.config` only takes a hash of options. For `database_url` Include the full database URL, including protocol, username, pass, domain, and database name. You can also pass in a `type_map` option which takes a type map object for converting result values.

```rb
require 'qx'

Qx.config(database_url: "postgres://username:password@domain/db_name")
```

`.config` is best called once when your app is starting up. In rails you do not need to pass in the database URL, as ActiveRecord will already be initialized and Qx will simply make use of that.

# Qx.execute(sql, options), expr.execute(sql, options)

You can execute any SQL string or object using `.execute` or `#execute`.

```rb
expr = Qx.select(:x).from(:y).where("x = $n", n: 1)
expr.execute(verbose: true)
Qx.execute(expr, format: 'csv')
# Or raw:
Qx.execute("SELECT x FROM y WHERE x = $n", n: 1)
```

`.execute` takes an optional options hash as its second argument, which can have:

* verbose: defaults to false. Will print the query string if true.
* format: defaults to 'hash'. If set to 'hash', returns array of hashes. If set to 'csv', returns a CSV-style array of arrays (see below).

### hash format

By default, `.execute` has the format of `'hash'`. This means it returns an array of hashes, where each hash has its keys set to your selected column names and values set to the result values.

If the result is empty, it returns an empty array. All results will be contained in an array.

### csv format

If you set `format: 'csv'` in your execution options, you will get back a CSV-style array of rows.

The first row will be the headers -- ie. all of the column names you selected on.

All the subsequent arrays will be the rows values for every result.

CSV format is useful for exports or for saving memory in large selects.


# API

For now, please see [/test/qx_test.rb](/test/qx_test.rb) to see the full API. 

## shortcut / helper functions

Some convenience functions are provided that compose some of SQL expressions.

### Qx.fetch(table_name, ids_or_data)

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

### expr.common_values(hash)

If you're bulk inserting but want some common values in all your rows, you can do a single call to .common_values

```rb
expr = Qx.insert_into(:table_name)
  .values([{x: 1}, {x: 2}])
  .common_values({y: 'common'})
# INSERT INTO "table_name" ("x", "y")
# VALUES (1, 'common'), (2, 'common')
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
```




