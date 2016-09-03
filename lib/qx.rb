require 'active_record'
require 'colorize'
class Qx

  ## 
  # Initialize the database connection using a database url
  # Running this is required for #execute to work
  # Pass in a hash. For now, it only takes on key called :database_url
  # Include the full url including userpass and database name
  # For example:
  # Qx.config(database_url: 'postgres://admin:password@localhost/database_name')
  @@type_map = nil
  def self.config(h)
    @@type_map = h[:type_map]
  end

  # Qx.new, only used internally
  def initialize(tree)
    @tree = tree
    return self
  end

  def self.transaction(&block)
    ActiveRecord::Base.transaction do
      yield block
    end
  end

  def self.parse_select(expr)
    str =  'SELECT'
    str += " DISTINCT ON (#{expr[:DISTINCT_ON].map(&:to_s).join(', ')})" if expr[:DISTINCT_ON]
    str += ' ' + expr[:SELECT].map{|expr| expr.is_a?(Qx) ? expr.parse : expr}.join(", ")
    throw ArgumentError.new("FROM clause is missing for SELECT") unless expr[:FROM]
    str += ' FROM ' + expr[:FROM]
    str += expr[:JOIN].map{|from, cond| " JOIN #{from} ON #{cond}"}.join if expr[:JOIN]
    str += expr[:LEFT_JOIN].map{|from, cond| " LEFT JOIN #{from} ON #{cond}"}.join if expr[:LEFT_JOIN]
    str += ' WHERE ' + expr[:WHERE].map{|w| "(#{w})"}.join(" AND ") if expr[:WHERE]
    str += ' GROUP BY ' + expr[:GROUP_BY].join(", ") if expr[:GROUP_BY]
    str += ' HAVING ' + expr[:HAVING].map{|h| "(#{h})"}.join(" AND ") if expr[:HAVING]
    str += ' ORDER BY ' + expr[:ORDER_BY].map{|col, order| col + (order ? ' ' + order : '')}.join(", ") if expr[:ORDER_BY]
    str += ' LIMIT ' + expr[:LIMIT] if expr[:LIMIT]
    str += ' OFFSET ' + expr[:OFFSET] if expr[:OFFSET]
    str = "(#{str}) AS #{expr[:AS]}" if expr[:AS]
    str = "EXPLAIN #{str}" if expr[:EXPLAIN]
    return str
  end

  # Parse a Qx expression tree into a single query string that can be executed
  # http://www.postgresql.org/docs/9.0/static/sql-commands.html
  def self.parse(expr)
    if expr.is_a?(String)
      return expr # already parsed
    elsif expr.is_a?(Array)
      return expr.join(",")
    elsif expr[:INSERT_INTO]
      str =  "INSERT INTO #{expr[:INSERT_INTO]} (#{expr[:INSERT_COLUMNS].join(", ")})"
      throw ArgumentError.new("VALUES (or SELECT) clause is missing for INSERT INTO") unless expr[:VALUES] || expr[:SELECT]
      if expr[:SELECT]
        str += ' ' + parse_select(expr)
      else
        str += " VALUES #{expr[:VALUES].map{|vals| "(#{vals.join(", ")})"}.join(", ")}"
      end
      str += " RETURNING " + expr[:RETURNING].join(", ") if expr[:RETURNING]
    elsif expr[:SELECT]
      str = parse_select(expr)
    elsif expr[:DELETE_FROM]
      str =  'DELETE FROM ' + expr[:DELETE_FROM]
      str += ' WHERE ' + expr[:WHERE].map{|w| "(#{w})"}.join(" AND ") if expr[:WHERE]
      str += " RETURNING " + expr[:RETURNING].join(", ") if expr[:RETURNING]
    elsif expr[:UPDATE]
      str =  'UPDATE ' + expr[:UPDATE]
      throw ArgumentError.new("SET clause is missing for UPDATE") unless expr[:SET]
      str += ' SET ' + expr[:SET]
      str += ' FROM ' + expr[:FROM] if expr[:FROM]
      str += ' WHERE ' + expr[:WHERE].map{|w| "(#{w})"}.join(" AND ") if expr[:WHERE]
      str += " RETURNING " + expr[:RETURNING].join(", ") if expr[:RETURNING]
    end
    return str
  end
  # An instance method version of the above
  def parse; Qx.parse(@tree); end

  # Qx.select("id").from("supporters").execute
  def execute(options={})
    expr = Qx.parse(@tree).to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    return Qx.execute_raw(expr, options)
  end
  alias_method :ex, :execute

  # Can pass in an expression string or another Qx object
  # Qx.execute("SELECT id FROM table_name", {format: 'csv'})
  # Qx.execute(Qx.select("id").from("table_name"))
  def self.execute(expr, data={}, options={})
    return expr.execute(data) if expr.is_a?(Qx)
    interpolated = Qx.interpolate_expr(expr, data)
    return self.execute_raw(interpolated, options)
  end

  # options
  #   verbose: print the query
  #   format: 'csv' | 'hash'    give data csv style with Arrays -- good for exports or for saving memory
  def self.execute_raw(expr, options={})
    puts expr if options[:verbose]
    result = ActiveRecord::Base.connection.execute(expr)
    result.map_types!(@@type_map) if @@type_map
    if options[:format] == 'csv'
      data = result.map{|h| h.values}
      data.unshift((result.first || {}).keys)
    else
      data = result.map{|h| h}
    end
    result.clear
    data = data.map{|row| apply_nesting(row)} if options[:nesting]
    return data
  end

  # helpers for JSON conversion
  def to_json(name)
    name = name.to_s
    Qx.select("array_to_json(array_agg(row_to_json(#{name})))").from(self.as(name))
  end

  # -- Top-level clauses

  def self.select(*cols)
    self.new(SELECT: cols)
  end
  def select(*cols)
    @tree[:SELECT] = cols
    self
  end
  def self.insert_into(table_name, cols=[])
    self.new(INSERT_INTO: Qx.quote_ident(table_name), INSERT_COLUMNS: cols.map{|c| Qx.quote_ident(c)})
  end
  def insert_into(table_name, cols=[])
    @tree[:INSERT_INTO] = Qx.quote_ident(table_name)
    @tree[:INSERT_COLUMNS] = cols.map{|c| Qx.quote_ident(c)}
    self
  end
  def self.delete_from(table_name)
    self.new(DELETE_FROM: Qx.quote_ident(table_name))
  end
  def delete_from(table_name)
    @tree[:DELETE_FROM] = Qx.quote_ident(table_name)
    self
  end
  def self.update(table_name)
    self.new(UPDATE: Qx.quote_ident(table_name))
  end
  def update(table_name)
    @tree[:UPDATE] = Qx.quote_ident(table_name)
    self
  end

  # -- Sub-clauses

  # - SELECT sub-clauses

  def distinct_on(*cols)
    @tree[:DISTINCT_ON] = cols
    self
  end

  def from(expr)
    @tree[:FROM] = expr.is_a?(Qx) ? expr.parse : expr.to_s
    self
  end
  def as(table_name)
    @tree[:AS] = Qx.quote_ident(table_name)
    self
  end

  # Clauses are pairs of expression and data
  def where(*clauses)
    ws = Qx.get_where_params(clauses)
    @tree[:WHERE] = Qx.parse_wheres(ws)
    self
  end
  def and_where(*clauses)
    ws = Qx.get_where_params(clauses)
    @tree[:WHERE] ||= []
    @tree[:WHERE].concat(Qx.parse_wheres(ws))
    self
  end

  def group_by(*cols)
    @tree[:GROUP_BY] = cols.map{|c| c.to_s}
    self
  end

  def order_by(*cols)
    orders = /(asc)|(desc)( nulls (first)|(last))?/i
    # Sanitize out invalid order keywords
    @tree[:ORDER_BY] = cols.map{|col, order| [col.to_s, order.to_s.downcase.strip.match(order.to_s.downcase) ? order.to_s.upcase : nil]}
    self
  end

  def having(expr, data={})
    @tree[:HAVING] = [Qx.interpolate_expr(expr, data)]
    self
  end
  def and_having(expr, data={})
    @tree[:HAVING].push(Qx.interpolate_expr(expr, data))
    self
  end

  def limit(n)
    @tree[:LIMIT] = n.to_i.to_s
    self
  end

  def offset(n)
    @tree[:OFFSET] = n.to_i.to_s
    self
  end

  def join(*joins)
    js = Qx.get_join_param(joins)
    @tree[:JOIN] = Qx.parse_joins(js)
    self
  end
  def add_join(*joins)
    js = Qx.get_join_param(joins)
    @tree[:JOIN] ||= []
    @tree[:JOIN].concat(Qx.parse_joins(js))
    self
  end
  def left_join(*joins)
    js = Qx.get_join_param(joins)
    @tree[:LEFT_JOIN] = Qx.parse_joins(js)
    self
  end
  def add_left_join(*joins)
    js = Qx.get_join_param(joins)
    @tree[:LEFT_JOIN] ||= []
    @tree[:LEFT_JOIN].concat(Qx.parse_joins(js))
    self
  end

  # - INSERT INTO / UPDATE

  # Allows three formats:
  #   insert.values([[col1, col2], [val1, val2], [val3, val3]], options)
  #   insert.values([{col1: val1, col2: val2}, {col1: val3, co2: val4}], options)
  #   insert.values({col1: val1, col2: val2}, options)  <- only for single inserts
  def values(vals)
    if vals.is_a?(Array) && vals.first.is_a?(Array)
      cols = vals.first
      data = vals[1..-1]
    elsif vals.is_a?(Array) && vals.first.is_a?(Hash)
      hashes = vals.map{|h| h.sort.to_h} # Make sure hash keys line up with all row data
      cols = hashes.first.keys
      data = hashes.map{|h| h.values}
    elsif vals.is_a?(Hash)
      cols = vals.keys
      data = [vals.values]
    end
    @tree[:VALUES] = data.map{|vals| vals.map{|d| Qx.quote(d)}}
    @tree[:INSERT_COLUMNS] = cols.map{|c| Qx.quote_ident(c)}
    self
  end

  # A convenience function for setting the same values across all inserted rows
  def common_values(h)
    cols = h.keys.map{|col| Qx.quote_ident(col)}
    data = h.values.map{|val| Qx.quote(val)}
    @tree[:VALUES] = @tree[:VALUES].map{|row| row.concat(data)}
    @tree[:INSERT_COLUMNS] = @tree[:INSERT_COLUMNS].concat(cols)
    self
  end

  # add timestamps to an insert or update
  def ts
    now = "'#{Time.now.utc}'"
    if @tree[:VALUES]
      @tree[:INSERT_COLUMNS].concat ['created_at', 'updated_at']
      @tree[:VALUES] = @tree[:VALUES].map{|arr| arr.concat [now, now]}
    elsif @tree[:SET]
      @tree[:SET] += ", updated_at = #{now}"
    end
    self
  end
  alias_method :timestamps, :ts

  def returning(*cols)
    @tree[:RETURNING] = cols.map{|c| Qx.quote_ident(c)}
    self
  end

  # Vals can be a raw SQL string or a hash of data
  def set(vals)
    if vals.is_a? Hash
      vals = vals.map{|key, val| "#{Qx.quote_ident(key)} = #{Qx.quote(val)}"}.join(", ")
    end
    @tree[:SET] = vals.to_s
    self
  end

  def explain
    @tree[:EXPLAIN] = true
    self
  end

  # -- Helpers!

  def self.fetch(table_name, data, options={})
    expr = Qx.select('*').from(table_name)
    if data.is_a?(Hash)
      expr = data.reduce(expr){|acc, pair| acc.and_where("#{pair.first} IN ($vals)", vals: Array(pair.last))}
    else
      expr = expr.where("id IN ($ids)", ids: Array(data))
    end
    result = expr.execute(options)
    return result
  end

  # Given a Qx expression, add a LIMIT and OFFSET for pagination
  def paginate(current_page, page_length)
    current_page = 1 if current_page.nil? || current_page < 1
    self.limit(page_length).offset((current_page - 1) * page_length)
  end

  def pp
    str = self.parse
    # Colorize some tokens
    # TODO indent by paren levels
    str = str
      .gsub(/(FROM|WHERE|VALUES|SET|SELECT|UPDATE|INSERT INTO|DELETE FROM)/){"#{$1}".blue.bold}
      .gsub(/(\(|\))/){"#{$1}".cyan}
      .gsub("$Q$", "'")
    return str
  end

  # -- utils

  def tree; @tree; end

  # Safely interpolate some data into a SQL expression
  def self.interpolate_expr(expr, data={})
    expr.to_s.gsub(/\$\w+/) do |match|
      val = data[match.gsub(/[ \$]*/, '').to_sym]
      vals = val.is_a?(Array) ? val : [val]
      vals.map{|x| Qx.quote(x)}.join(", ")
    end
  end

  # Quote a string for use in sql to prevent injection or weird errors
  # Always use this for all values!
  # Just uses double-dollar quoting universally. Should be generally safe and easy.
  # Will return an unquoted value it it's a Fixnum
  def self.quote(val)
    if val.is_a?(Qx)
      val.parse
    elsif val.is_a?(Fixnum)
      val.to_s
    elsif val.is_a?(Time)
      "'" + val.to_s + "'" # single-quoted times for a little better readability
    elsif val == nil
      "NULL"
    elsif !!val == val # is a boolean
      val ? "'t'" : "'f'"
    else
      return "$Q$" + val.to_s + "$Q$"
    end
  end

  # Double-quote sql identifiers (or parse Qx trees for subqueries)
  def self.quote_ident(expr)
    if expr.is_a?(Qx)
      Qx.parse(expr.tree)
    else
      expr.to_s.split('.').map{|s| s == '*' ? s : "\"#{s}\""}.join('.')
    end
  end

private # Internal utils

  # Turn join params into something that .parse can use
  def self.parse_joins(js)
    js.map{|table, cond, data| [table.is_a?(Qx) ? table.parse : table, Qx.interpolate_expr(cond, data)]}
  end

  # Given an array, determine if it has the form
  # [[join_table, join_on, data], ...]
  # or
  # [join_table, join_on, data]
  # Always return the former format
  def self.get_join_param(js)
    js.first.is_a?(Array) ? js : [[js.first, js[1], js[2]]]
  end
  
  # given either a single hash or a string expr + data, parse it into a single string expression
  def self.parse_wheres(clauses)
    clauses.map do |expr, data|
      if expr.is_a?(Hash)
        expr.map{|key, val| "#{Qx.quote_ident(key)} IN (#{Qx.quote(val)})"}.join(" AND ")
      else
        Qx.interpolate_expr(expr, data)
      end
    end
  end

  # Similar to get_joins_params, except each where clause is a pair, not a triplet
  def self.get_where_params(ws)
    ws.first.is_a?(Array) ? ws : [[ws.first, ws[1]]]
  end
  
  # given either a single, hash, array of hashes, or csv style, turn it all into csv style
  # util for INSERT INTO x (y) VALUES z
  def self.parse_val_params(vals)
    if vals.is_a?(Array) && vals.first.is_a?(Array)
      cols = vals.first
      data = vals[1..-1]
    elsif vals.is_a?(Array) && vals.first.is_a?(Hash)
      hashes = vals.map{|h| h.sort.to_h}
      cols = hashes.first.keys
      data = hashes.map{|h| h.values}
    elsif vals.is_a?(Hash)
      cols = vals.keys
      data = [vals.values]
    end
    return [cols, data]
  end


end

