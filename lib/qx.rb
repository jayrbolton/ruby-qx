require 'uri'
require 'active_record'

class Qx

  ## 
  # Initialize the database connection using a database url
  # Running this is required for #execute to work
  # Pass in a hash. For now, it only takes on key called :database_url
  # Include the full url including userpass and database name
  # For example:
  # Qx.config(database_url: 'postgres://admin:password@localhost/database_name')
  def self.config(h)
    ActiveRecord::Base.establish_connection(h[:database_url])
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

  # Parse a Qx expression tree into a single query string that can be executed
  # http://www.postgresql.org/docs/9.0/static/sql-commands.html
  def self.parse(expr)
    if expr.is_a?(String)
      return expr # already parsed
    elsif expr.is_a?(Array)
      return expr.join(",")
    elsif expr[:SELECT]
      str =  'SELECT '  + expr[:SELECT].join(", ")
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
    elsif expr[:INSERT_INTO]
      str =  "INSERT INTO #{expr[:INSERT_INTO]} (#{expr[:VALUES].first.join(", ")})"
      str += " VALUES #{expr[:VALUES][1].map{|vals| "(#{vals.join(", ")})"}.join(", ")}"
      str += " RETURNING " + expr[:RETURNING].join(", ") if expr[:RETURNING]
    elsif expr[:DELETE_FROM]
      str =  'DELETE FROM ' + expr[:DELETE_FROM]
      str += ' WHERE ' + expr[:WHERE].map{|w| "(#{w})"}.join(" AND ") if expr[:WHERE]
      str += " RETURNING " + expr[:RETURNING].join(", ") if expr[:RETURNING]
    elsif expr[:UPDATE]
      str =  'UPDATE ' + expr[:UPDATE]
      str += ' SET ' + expr[:SET].map{|key, val| "#{key} = #{val}"}.join(", ")
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

  # Can pass in an expression string or another Qx object
  # Qx.execute("SELECT id FROM table_name", {format: 'csv'})
  # Qx.execute(Qx.select("id").from("table_name"))
  def self.execute(expr, options={})
    return expr.is_a?(String) ? self.execute_raw(expr, options) : expr.execute(options)
  end

  # options
  #   verbose: print the query
  #   format: 'csv' | 'hash'    give data csv style with Arrays -- good for exports or for saving memory
  def self.execute_raw(expr, options={})
    puts expr if options[:verbose]
    result = ActiveRecord::Base.connection.execute(expr)
    if options[:format] == 'csv'
      data = result.map{|h| h.values}
      data.unshift((result.first || {}).keys)
    else
      data = result.map{|h| h}
    end
    result.clear
    return data.count <= 1 ? data.first : data
  end

  # -- Top-level clauses

  def self.select(*cols)
    self.new(SELECT: cols)
  end
  def self.insert_into(table_name)
    self.new(INSERT_INTO: Qx.quote_ident(table_name))
  end
  def self.delete_from(table_name)
    self.new(DELETE_FROM: Qx.quote_ident(table_name))
  end
  def self.update(table_name)
    self.new(UPDATE: Qx.quote_ident(table_name))
  end

  # -- Sub-clauses

  # - SELECT sub-clauses

  def from(expr)
    @tree[:FROM] = Qx.quote_ident(expr)
    self
  end
  def as(table_name)
    @tree[:AS] = Qx.quote_ident(table_name)
    self
  end

  def where(expr, data={})
    @tree[:WHERE] = [Qx.interpolate_expr(expr, data)]
    self
  end
  def and_where(expr, data={})
    @tree[:WHERE] ||= []
    @tree[:WHERE].push(Qx.interpolate_expr(expr, data))
    self
  end

  def group_by(*cols)
    @tree[:GROUP_BY] = cols.map{|c| Qx.quote_ident(c)}
    self
  end

  def order_by(*cols)
    orders = ['asc', 'desc']
    # Sanitize out invalid order keywords
    @tree[:ORDER_BY] = cols.map{|col, order| [Qx.quote_ident(col), orders.include?(order.to_s.downcase) ? order.to_s : nil]}
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
    @tree[:JOIN] ||= []
    @tree[:JOIN].concat(joins.map{|table, cond, data| [Qx.quote_ident(table), Qx.interpolate_expr(cond, data)]})
    self
  end
  def left_join(*joins)
    @tree[:LEFT_JOIN] ||= []
    @tree[:LEFT_JOIN].concat(joins.map{|table, cond, data| [Qx.quote_ident(table), Qx.interpolate_expr(cond, data)]})
    self
  end

  # - INSERT INTO / UPDATE

  # Allows three formats:
  #   insert.values([col1, col2], [[val1, val2], [val3, val4]])
  #   insert.values([{col1: val1, col2: val2}, {col1: val3, co2: val4}])
  #   insert.values({col1: val1, col2: val2})  <- only for single inserts
  def values(x, y=nil)
    if x.is_a?(Array) && y.is_a?(Array)
      cols = x
      data = y
    elsif x.is_a?(Array) && x.first.is_a?(Hash)
      hashes = x.map{|h| h.sort.to_h}
      cols = hashes.first.keys
      data = hashes.map{|h| h.values}
    elsif x.is_a?(Hash)
      cols = x.keys
      data = [x.values]
    end
    @tree[:VALUES] = [cols.map{|c| Qx.quote_ident(c)}, data.map{|vals| vals.map{|d| Qx.quote(d)}}]
    self
  end

  # add timestamps to an insert or update
  def ts
    now = "'#{Time.now.utc}'"
    if @tree[:VALUES]
      @tree[:VALUES].first.concat ['created_at', 'updated_at']
      @tree[:VALUES][1] = @tree[:VALUES][1].map{|arr| arr.concat [now, now]}
    elsif @tree[:SET]
      @tree[:SET].push ['updated_at', now]
    end
    self
  end

  def returning(*cols)
    @tree[:RETURNING] = cols.map{|c| Qx.quote_ident(c)}
    self
  end

  def set(hash)
    @tree[:SET] = hash.map{|col, val| [Qx.quote_ident(col), Qx.quote(val)]}
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

  # -- utils

  def tree; @tree; end

  # Safely interpolate some data into a SQL expression
  def self.interpolate_expr(expr, data={})
    expr.to_s.gsub(/\$\w+/) do |match|
      val = data[match.gsub(/[ \$]*/, '').to_sym]
      Array(val).map{|x| Qx.quote(x)}.join(", ")
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

end

