require './lib/qx.rb'
require 'minitest/autorun'
require 'pry'

class QxTest < Minitest::Test

  def setup
    Qx.config(database_url: 'postgres://admin:password@localhost/qx_test')
  end

  def test_select_from
    parsed = Qx.select(:id, "name").from(:table_name).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name")
  end

  def test_select_as
    parsed = Qx.select(:id, "name").from(:table_name).as(:alias).parse
    assert_equal parsed, %Q((SELECT id, name FROM "table_name") AS "alias")
  end
  
  def test_select_where
    parsed = Qx.select(:id, "name").from(:table_name).where("x = $y OR a = $b", y: 1, b: 2).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" WHERE (x = 1 OR a = 2))
  end
  def test_select_where_hash
    parsed = Qx.select(:id, "name").from(:table_name).where(x: 1, y: 2).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" WHERE ("x" IN (1) AND "y" IN (2)))
  end
  def test_select_and_where
    parsed = Qx.select(:id, "name").from(:table_name).where("x = $y", y: 1).and_where("a = $b", b: 2).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" WHERE (x = 1) AND (a = 2))
  end
  def test_select_and_where_hash
    parsed = Qx.select(:id, "name").from(:table_name).where("x = $y", y: 1).and_where(a: 2).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" WHERE (x = 1) AND ("a" IN (2)))
  end
  
  def test_select_and_group_by
    parsed = Qx.select(:id, "name").from(:table_name).group_by("col1", "col2").parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" GROUP BY col1, col2)
  end
  
  def test_select_and_order_by
    parsed = Qx.select(:id, "name").from(:table_name).order_by("col1", "col2").parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" ORDER BY col1, col2)
  end

  def test_select_having
    parsed = Qx.select(:id, "name").from(:table_name).having("COUNT(col1) > $n", n: 1).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" HAVING (COUNT(col1) > 1))
  end
  def test_select_and_having
    parsed = Qx.select(:id, "name").from(:table_name).having("COUNT(col1) > $n", n: 1).and_having("SUM(col2) > $m", m: 2).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" HAVING (COUNT(col1) > 1) AND (SUM(col2) > 2))
  end

  def test_select_limit
    parsed = Qx.select(:id, "name").from(:table_name).limit(10).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" LIMIT 10)
  end
  def test_select_offset
    parsed = Qx.select(:id, "name").from(:table_name).offset(10).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" OFFSET 10)
  end

  def test_select_join
    parsed = Qx.select(:id, "name").from(:table_name).join(['assoc1', 'assoc1.table_name_id=table_name.id']).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" JOIN assoc1 ON assoc1.table_name_id=table_name.id)
  end

  def test_select_left_join
    parsed = Qx.select(:id, "name").from(:table_name).left_join(['assoc1', 'assoc1.table_name_id=table_name.id']).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" LEFT JOIN assoc1 ON assoc1.table_name_id=table_name.id)
  end

  def test_select_where_subquery
    parsed = Qx.select(:id, "name").from(:table_name).where("id IN ($ids)", ids: Qx.select("id").from("assoc")).parse
    assert_equal parsed, %Q(SELECT id, name FROM "table_name" WHERE (id IN (SELECT id FROM "assoc")))
  end

  def test_select_join_subquery
    parsed = Qx.select(:id).from(:table).join([Qx.select(:id).from(:assoc).as(:assoc), "assoc.table_id=table.id"]).parse
    assert_equal parsed, %Q(SELECT id FROM "table" JOIN (SELECT id FROM "assoc") AS "assoc" ON assoc.table_id=table.id)
  end

  def test_select_from_subquery
    parsed = Qx.select(:id).from(Qx.select(:id).from(:table).as(:table)).parse
    assert_equal parsed, %Q(SELECT id FROM (SELECT id FROM "table") AS "table")
  end

  def test_select_integration
    parsed = Qx.select(:id)
      .from(:table)
      .join([Qx.select(:id).from(:assoc).as(:assoc), 'assoc.table_id=table.id'])
      .left_join(['lefty', 'lefty.table_id=table.id'])
      .where('x = $n', n: 1)
      .and_where('y = $n', n: 1)
      .group_by(:x)
      .order_by(:y)
      .having('COUNT(x) > $n', n: 1)
      .and_having('COUNT(y) > $n', n: 1)
      .limit(10)
      .offset(10)
      .parse
    assert_equal parsed, %Q(SELECT id FROM "table" JOIN (SELECT id FROM "assoc") AS "assoc" ON assoc.table_id=table.id LEFT JOIN lefty ON lefty.table_id=table.id WHERE (x = 1) AND (y = 1) GROUP BY x HAVING (COUNT(x) > 1) AND (COUNT(y) > 1) ORDER BY y LIMIT 10 OFFSET 10)
  end

  def test_insert_timestamps
    now = Time.now.utc
    parsed = Qx.insert_into(:table_name).values({x: 1}).ts.parse
    assert_equal parsed, %Q(INSERT INTO "table_name" ("x", created_at, updated_at) VALUES (1, '#{now}', '#{now}'))
  end

  def test_update_timestamps
    now = Time.now.utc
    parsed = Qx.update(:table_name).set(x: 1).ts.parse
    assert_equal parsed, %Q(UPDATE "table_name" SET "x" = 1, updated_at = '#{now}')
  end
end
