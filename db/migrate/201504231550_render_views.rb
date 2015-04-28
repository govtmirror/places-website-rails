A
require "migrate"

class RenderViews < ActiveRecord::Migration
  def up
    execute <<-SQL
      CREATE OR REPLACE VIEW api_current_nodes AS 
       SELECT current_nodes.id,
          current_nodes.visible,
          current_nodes.version,
          current_nodes.changeset_id AS changeset,
          timezone('UTC'::text, current_nodes."timestamp") AS "timestamp",
          users.display_name AS "user",
          changesets.user_id AS uid,
          current_nodes.latitude::double precision / 10000000::double precision AS lat,
          current_nodes.longitude::double precision / 10000000::double precision AS lon,
          ( SELECT json_agg(tags.*) AS json_agg
                 FROM ( SELECT current_node_tags.k,
                          current_node_tags.v
                         FROM current_node_tags
                        WHERE current_node_tags.node_id = current_nodes.id) tags) AS tag
         FROM current_nodes
           JOIN changesets ON current_nodes.changeset_id = changesets.id
           JOIN users ON changesets.user_id = users.id;

      CREATE OR REPLACE VIEW api_current_relations AS 
       SELECT current_relations.id,
          current_relations.visible,
          current_relations.version,
          current_relations.changeset_id AS changeset,
          timezone('UTC'::text, current_relations."timestamp") AS "timestamp",
          users.display_name AS "user",
          changesets.user_id AS uid,
          ( SELECT json_agg(members.*) AS json_agg
                 FROM ( SELECT lower(relation_members.member_type::text) AS type,
                          relation_members.member_id AS ref,
                          relation_members.member_role AS role
                         FROM relation_members
                        WHERE relation_members.relation_id = current_relations.id) members) AS member,
          ( SELECT json_agg(tags.*) AS json_agg
                 FROM ( SELECT current_relation_tags.k,
                          current_relation_tags.v
                         FROM current_relation_tags
                        WHERE current_relation_tags.relation_id = current_relations.id) tags) AS tag
         FROM current_relations
           JOIN changesets ON current_relations.changeset_id = changesets.id
           JOIN users ON changesets.user_id = users.id;

      CREATE OR REPLACE VIEW api_current_ways AS 
       SELECT current_ways.id,
          current_ways.visible,
          current_ways.version,
          current_ways.changeset_id AS changeset,
          timezone('UTC'::text, current_ways."timestamp") AS "timestamp",
          users.display_name AS "user",
          changesets.user_id AS uid,
          ( SELECT json_agg(nodes.*) AS json_agg
                 FROM ( SELECT current_way_nodes.node_id AS ref
                         FROM current_way_nodes
                        WHERE current_way_nodes.way_id = current_ways.id AND current_ways.version = current_ways.version
                        ORDER BY current_way_nodes.sequence_id) nodes) AS nd,
          ( SELECT json_agg(tags.*) AS json_agg
                 FROM ( SELECT current_way_tags.k,
                          current_way_tags.v
                         FROM current_way_tags
                        WHERE current_way_tags.way_id = current_ways.id) tags) AS tag
         FROM current_ways
           JOIN changesets ON current_ways.changeset_id = changesets.id
           JOIN users ON changesets.user_id = users.id;
    SQL
  end
  def down
    execute <<-SQL
      DROP VIEW api_current_node;
      DROP VIEW api_current_way;
      DROP VIEW api_current_relation;
    SQL
  end
end
