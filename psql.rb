# Some convenience wrappers around the postgresql gem, allowing us to avoid activerecord dependency
# combine usage of this library with Qexpr
# Returns hamster vectors and hashes for all data.

require 'pg'
require 'hamster'
require 'colorize'

# Initialize the database connection

env = ENV['RAILS_ENV']
if env == 'production' || env == 'staging'
	db = URI.parse(ENV['DATABASE_URL'])
	options = {host: db.host, port: db.port, user: db.user, password: db.password, dbname: db.path[1..-1]}
elsif env == 'development'
	options = {dbname: 'commitchange_development'}
elsif ENV['CIRCLECI']
  options = {dbname: 'circle_test', user: 'ubuntu'}
else
  options = {dbname: "commitchange_test"}
end
Conn = PG::Connection.open(options)
Conn.type_map_for_results = PG::BasicTypeMapForResults.new Conn

# Make certain we are using UTC
ENV['TZ'] = 'UTC'
Conn.exec("set timezone='UTC'")

module Psql

  # Execute a sql statement (string), returning a Hamster array of Hamster vectors (lol)
  def self.execute(statement)
    puts statement if ENV['RAILS_ENV'] != 'production' && ENV['RAILS_LOG_LEVEL'] == 'debug' # log to STDOUT on dev/staging
    res = Conn.exec(raw_expr_str(statement))
    vec = Hamster::Vector[*res.map{|h| Hamster::Hash[h]}]
    res.clear
    return vec
  end

  # A variation of execute that returns a vector of vectors rather than a vector of hashes
  # Useful and faster for creating CSV's
  def self.execute_vectors(statement)
    puts statement if ENV['RAILS_ENV'] != 'production' && ENV['RAILS_LOG_LEVEL'] == 'debug' # log to STDOUT on dev/staging
    raw_str = statement.to_s.uncolorize.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
    res = Conn.exec(raw_expr_str(statement))
    return Hamster::Vector[] if res.count == 0
    vec = Hamster::Vector[Hamster::Vector[*res.first.keys]].concat(res.map{|h| Hamster::Vector[*h.values]})
    res.clear
    return vec
  end

  def self.transaction(&block)
    Conn.transaction do
      yield block
    end
  end

private

  # Raw expression string
  def self.raw_expr_str(statement)
    statement.to_s.uncolorize.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
  end

end
