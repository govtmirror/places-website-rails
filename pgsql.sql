-- #NPS# -- Tasks to run before import
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_topology;
CREATE EXTENSION hstore;

-- Create the tag_list and the park_unit_boundaries tables

-- #NPS# -- Large Script
-- https://raw.githubusercontent.com/openstreetmap/osmosis/master/package/script/pgsnapshot_schema_0.6.sql
-- Database creation script for the snapshot PostgreSQL schema.

-- Drop all tables if they exist.
DROP TABLE IF EXISTS actions;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS nodes;
DROP TABLE IF EXISTS ways;
DROP TABLE IF EXISTS way_nodes;
DROP TABLE IF EXISTS relations;
DROP TABLE IF EXISTS relation_members;
DROP TABLE IF EXISTS schema_info;

-- Drop all stored procedures if they exist.
DROP FUNCTION IF EXISTS osmosisUpdate();


-- Create a table which will contain a single row defining the current schema version.
CREATE TABLE schema_info (
    version integer NOT NULL
);


-- Create a table for users.
CREATE TABLE users (
    id int NOT NULL,
    name text NOT NULL
);


-- Create a table for nodes.
CREATE TABLE nodes (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore
);
-- Add a postgis point column holding the location of the node.
SELECT AddGeometryColumn('nodes', 'geom', 4326, 'POINT', 2);


-- Create a table for ways.
CREATE TABLE ways (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore,
    nodes bigint[]
);


-- Create a table for representing way to node relationships.
CREATE TABLE way_nodes (
    way_id bigint NOT NULL,
    node_id bigint NOT NULL,
    sequence_id int NOT NULL
);


-- Create a table for relations.
CREATE TABLE relations (
    id bigint NOT NULL,
    version int NOT NULL,
    user_id int NOT NULL,
    tstamp timestamp without time zone NOT NULL,
    changeset_id bigint NOT NULL,
    tags hstore
);

-- Create a table for representing relation member relationships.
CREATE TABLE relation_members (
    relation_id bigint NOT NULL,
    member_id bigint NOT NULL,
    member_type character(1) NOT NULL,
    member_role text NOT NULL,
    sequence_id int NOT NULL
);


-- Configure the schema version.
INSERT INTO schema_info (version) VALUES (6);


-- Add primary keys to tables.
ALTER TABLE ONLY schema_info ADD CONSTRAINT pk_schema_info PRIMARY KEY (version);

ALTER TABLE ONLY users ADD CONSTRAINT pk_users PRIMARY KEY (id);

ALTER TABLE ONLY nodes ADD CONSTRAINT pk_nodes PRIMARY KEY (id);

ALTER TABLE ONLY ways ADD CONSTRAINT pk_ways PRIMARY KEY (id);

ALTER TABLE ONLY way_nodes ADD CONSTRAINT pk_way_nodes PRIMARY KEY (way_id, sequence_id);

ALTER TABLE ONLY relations ADD CONSTRAINT pk_relations PRIMARY KEY (id);

ALTER TABLE ONLY relation_members ADD CONSTRAINT pk_relation_members PRIMARY KEY (relation_id, sequence_id);


-- Add indexes to tables.
CREATE INDEX idx_nodes_geom ON nodes USING gist (geom);

CREATE INDEX idx_way_nodes_node_id ON way_nodes USING btree (node_id);

CREATE INDEX idx_relation_members_member_id_and_type ON relation_members USING btree (member_id, member_type);


-- Set to cluster nodes by geographical location.
ALTER TABLE ONLY nodes CLUSTER ON idx_nodes_geom;

-- Set to cluster the tables showing relationship by parent ID and sequence
ALTER TABLE ONLY way_nodes CLUSTER ON pk_way_nodes;
ALTER TABLE ONLY relation_members CLUSTER ON pk_relation_members;

-- There are no sensible CLUSTER orders for users or relations.
-- Depending on geometry columns different clustings of ways may be desired.

-- Create the function that provides "unnest" functionality while remaining compatible with 8.3.
CREATE OR REPLACE FUNCTION unnest_bbox_way_nodes() RETURNS void AS $$
DECLARE
  previousId ways.id%TYPE;
  currentId ways.id%TYPE;
  result bigint[];
  wayNodeRow way_nodes%ROWTYPE;
  wayNodes ways.nodes%TYPE;
BEGIN
  FOR wayNodes IN SELECT bw.nodes FROM bbox_ways bw LOOP
    FOR i IN 1 .. array_upper(wayNodes, 1) LOOP
      INSERT INTO bbox_way_nodes (id) VALUES (wayNodes[i]);
    END LOOP;
  END LOOP;
END;
$$ LANGUAGE plpgsql;


-- Create customisable hook function that is called within the replication update transaction.
CREATE FUNCTION osmosisUpdate() RETURNS void AS $$
DECLARE
BEGIN
END;
$$ LANGUAGE plpgsql;

-- Manually set statistics for the way_nodes and relation_members table
-- Postgres gets horrible counts of distinct values by sampling random pages
-- and can be off by an 1-2 orders of magnitude

-- Size of the ways table / size of the way_nodes table
ALTER TABLE way_nodes ALTER COLUMN way_id SET (n_distinct = -0.08);

-- Size of the nodes table / size of the way_nodes table * 0.998
-- 0.998 is a factor for nodes not in ways
ALTER TABLE way_nodes ALTER COLUMN node_id SET (n_distinct = -0.83);

-- API allows a maximum of 2000 nodes/way. Unlikely to impact query plans.
ALTER TABLE way_nodes ALTER COLUMN sequence_id SET (n_distinct = 2000);

-- Size of the relations table / size of the relation_members table
ALTER TABLE relation_members ALTER COLUMN relation_id SET (n_distinct = -0.09);

-- Based on June 2013 data
ALTER TABLE relation_members ALTER COLUMN member_id SET (n_distinct = -0.62);

-- Based on June 2013 data. Unlikely to impact query plans.
ALTER TABLE relation_members ALTER COLUMN member_role SET (n_distinct = 6500);

-- Based on June 2013 data. Unlikely to impact query plans.
ALTER TABLE relation_members ALTER COLUMN sequence_id SET (n_distinct = 10000);

-- #NPS# ---------------------------------------------------------------------
-- NPS types
DROP TYPE IF EXISTS new_hstore CASCADE;
CREATE TYPE new_hstore AS (k text, v text);

DROP TYPE IF EXISTS new_relation_members CASCADE;
CREATE TYPE new_relation_members AS (relation_id bigint, member_id bigint, member_type text, member_role text, sequence_id integer);

-- Type: public.aggregate_way

-- DROP TYPE public.aggregate_way;

CREATE TYPE public.aggregate_way AS
   (geom public.geometry[],
    role text[]);
ALTER TYPE public.aggregate_way
  OWNER TO postgres;

-- #NPS# ---------------------------------------------------------------------
-- nps render functions

---------------------------------
-- TODO: This should read from the tag_list table

CREATE OR REPLACE FUNCTION public.o2p_calculate_zorder(text, char(1))
  RETURNS integer AS
$BODY$
DECLARE
  v_tag ALIAS for $1;
  v_element_type ALIAS for $2;
  v_zorder integer;
BEGIN

SELECT
  CASE
    WHEN v_element_type = 'N'::char(1) THEN
      CASE
        WHEN v_tag = 'Visitor Center' THEN 40
        WHEN v_tag = 'Ranger Station' THEN 38
        WHEN v_tag = 'Information' THEN 36
        WHEN v_tag = 'Lodge' THEN 34
        WHEN v_tag = 'Campground' THEN 32
        WHEN v_tag = 'Food Service' THEN 30
        WHEN v_tag = 'Store' THEN 28
        WHEN v_tag = 'Picnic Site' THEN 26
        WHEN v_tag = 'Picnic Table' THEN 26
        WHEN v_tag = 'Trailhead' THEN 24
        WHEN v_tag = 'Car Parking' THEN 22
        WHEN v_tag = 'Restrooms' THEN 20
        ELSE 0
      END
    WHEN v_element_type = 'W'::char(1) THEN 0
    ELSE 0
  END AS order
INTO
  v_zorder;

RETURN v_zorder;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
------------

-- Convert JSON to hstore
CREATE OR REPLACE FUNCTION public.json_to_hstore(
  json
)
  RETURNS hstore AS $json_to_hstore$
DECLARE
  v_json ALIAS for $1;
  v_hstore HSTORE;
BEGIN
SELECT
  hstore(array_agg(key), array_agg(value))
FROM
 json_each_text(v_json)
INTO
  v_hstore;

 RETURN v_hstore;
END;
$json_to_hstore$
LANGUAGE plpgsql;
-------------------------

-------------------------
CREATE OR REPLACE FUNCTION public.json_to_hstore(
  json
)
  RETURNS hstore AS $json_to_hstore$
DECLARE
  v_json ALIAS for $1;
  v_hstore HSTORE;
BEGIN
SELECT
  hstore(array_agg(key), array_agg(value))
FROM
 json_each_text(v_json)
INTO
  v_hstore;

 RETURN v_hstore;
END;
$json_to_hstore$
LANGUAGE plpgsql;
-------------------------

-- Function: public.o2p_get_type(hstore, text[], boolean)

-- DROP FUNCTION public.o2p_get_type(hstore, text[], boolean);

CREATE OR REPLACE FUNCTION public.o2p_get_type(
    hstore,
    text[],
    boolean)
  RETURNS text AS
$BODY$
DECLARE
  v_hstore ALIAS for $1;
  v_geometry_type ALIAS FOR $2;
  v_all ALIAS for $3;
  v_name TEXT;
  v_tag_count bigint;
BEGIN

SELECT
  ARRAY_LENGTH(ARRAY_AGG("key"),1)
FROM
  UNNEST(AKEYS(v_hstore)) "key"
WHERE
  "key" NOT LIKE 'nps:%'
INTO
  v_tag_count;


IF v_tag_count > 0 THEN
  SELECT
    "name"
  FROM (
    SELECT
      CASE 
        WHEN "geometry" && v_geometry_type THEN "name"
        ELSE null
      END as "name",
      max("hstore_len") AS "hstore_len",
      count(*) AS "match_count",
      max("matchscore") as "matchscore",
      "all_tags",
      bool_and("searchable") as "searchable"
    FROM (
      SELECT
        "name",
        "available_tags",
        "all_tags",
        "searchable",
        "matchscore",
        "geometry",
        each(v_hstore) AS "input_tags",
        "hstore_len"
      FROM (
        SELECT
          "name",
          each("tags") AS "available_tags",
          "tags" as "all_tags",
          "searchable",
          "matchscore",
          "geometry",
          "hstore_len"
        FROM (
          SELECT
            "hstore_tag_list"."name",
            "searchable",
            "matchscore",
            "geometry",
            (SELECT hstore(array_agg("key"), array_agg(hstore_tag_list.tags->"key")) from unnest(akeys(hstore_tag_list.tags)) "key" WHERE "key" NOT LIKE 'nps:%') "tags",
            (SELECT array_length(array_agg("key"),1) FROM unnest(akeys("hstore_tag_list"."tags")) "key" WHERE "key" NOT LIKE 'nps:%') "hstore_len"
          FROM
            (
              SELECT
                "name",
                json_to_hstore("tags") AS "tags",
                "searchable",
                "matchscore",
                "geometry"
              FROM
                "tag_list"
              WHERE
                ((ARRAY['point'] && v_geometry_type AND "tag_list"."geometry" && ARRAY['point']) OR
                (ARRAY['line','area'] && v_geometry_type AND "tag_list"."geometry" && ARRAY['line','area'])) AND
                (v_all OR (
                  -- "tag_list"."searchable" is null OR
                  "tag_list"."searchable" is true
                ))
            ) "hstore_tag_list"
        ) "available_tags"
      ) "explode_tags"
    ) "paired_tags"
    WHERE
      "available_tags" = "input_tags"  OR
      (hstore(available_tags)->'value' = '*' AND hstore(available_tags)->'key' = hstore(input_tags)->'key')
    GROUP BY
      "all_tags",
      "name",
      "geometry"
    ) "counted_tags"
  WHERE
    "hstore_len" = "match_count"
  ORDER BY
    "match_count" DESC,
    "searchable" DESC,
    "matchscore" DESC,
    avals("all_tags") && ARRAY['*']
  LIMIT
    1
  INTO
    v_name;
  ELSE
    SELECT null INTO v_name;
  END IF;

 RETURN v_name;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
ALTER FUNCTION public.o2p_get_type(hstore, text[], boolean)
  OWNER TO postgres;
-------------------

-- Function: public.o2p_calculate_nodes_to_line(bigint[])

-- DROP FUNCTION public.o2p_calculate_nodes_to_line(bigint[]);

CREATE OR REPLACE FUNCTION public.o2p_calculate_nodes_to_line(bigint[])
  RETURNS geometry AS
$BODY$
DECLARE
  v_nodes ALIAS for $1;
  v_line geometry;
BEGIN
-- looks up all the nodes and creates a linestring from them
SELECT
  ST_MakeLine(g.geom)
FROM (
  SELECT
    geom
  FROM
    nodes
    JOIN (
      SELECT 
        unnest(v_nodes) as node
    ) way ON nodes.id = way.node
) g
INTO
  v_line;

RETURN v_line;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
-------------------------------

CREATE OR REPLACE FUNCTION public.o2p_aggregate_relation(bigint)
  RETURNS aggregate_way AS
$BODY$
DECLARE
  v_rel_id ALIAS for $1;
  v_way geometry[];
  v_role text[];
BEGIN

SELECT
  array_agg(route),
  array_agg(member_role)
FROM (
  SELECT
    CASE
      WHEN direction = 'R' THEN st_reverse(st_makeline(st_reverse(way_geom)))
      ELSE st_makeline(way_geom)
    END route,
    member_role
  FROM (
    SELECT
      CASE
        WHEN new_line = true THEN
    CASE
      WHEN direction = 'N' THEN new_line_rank || sequence_id::text
      WHEN lead(new_line,1) OVER rw_seq = false THEN lead(new_line_rank,1) OVER rw_seq || direction
      ELSE new_line_rank || direction
    END
        ELSE new_line_rank || direction
      END grp,
      member_role,
      sequence_id,
      direction,
      way_geom
    FROM (
      SELECT
        way_geom,
        sequence_id,
        direction,
        new_line,
        member_role,
        sequence_id - rank() OVER (PARTITION BY new_line ORDER BY sequence_id) + 1 as new_line_rank
      FROM (
        SELECT
          sequence_id,
          member_role,
          CASE
            WHEN
              first_node = last_node
            THEN 'N'
            WHEN
              first_node = lag(last_node,1) OVER wr_seq OR
              last_node = lead(first_node,1) OVER wr_seq OR
              last_node = lag(last_node) OVER wr_seq
            THEN 'F'
            WHEN
              last_node = lag(first_node,1) OVER wr_seq OR
              first_node = lead(last_node,1) OVER wr_seq OR
              first_node = lag(first_node) OVER wr_seq
            THEN 'R'
            ELSE 'N'
          END as direction,
          CASE
            WHEN
              first_node = last_node THEN true
            WHEN
              first_node = lag(last_node,1) OVER wr_seq OR
              last_node = lag(first_node,1) OVER wr_seq OR
              first_node = lag(first_node) OVER wr_seq OR
              last_node = lag(last_node) OVER wr_seq
            THEN false
            ELSE true
          END as new_line,
          CASE
            WHEN
              first_node = lag(first_node) OVER wr_seq OR
              last_node = lag(last_node) OVER wr_seq
            THEN st_reverse(way_geom)
            ELSE way_geom
          END as way_geom
          FROM (
            SELECT
              ways.nodes[1] first_node,
              ways.nodes[array_length(ways.nodes, 1)] last_node,
              o2p_calculate_nodes_to_line(ways.nodes) as way_geom,
              member_role,
              sequence_id
            FROM
            relation_members JOIN
                ways ON ways.id = relation_members.member_id
              WHERE
                relation_id = v_rel_id AND -- relation: 2301099 is rt 13 (for testing)
                UPPER(member_type) = 'W'
              ORDER BY
                sequence_id
          ) way_rels
          WINDOW wr_seq as (
           ORDER BY way_rels.sequence_id
          )
      ) directioned_ways ORDER BY directioned_ways.sequence_id 
    ) ranked_ways
     WINDOW rw_seq as (
      ORDER BY ranked_ways.sequence_id
    )
    ORDER BY
      ranked_ways.sequence_id
  ) grouped_ways GROUP BY
    grp,
    direction,
    member_role
  ORDER BY
    min(sequence_id)
 ) ways_agg
  INTO
    v_way, v_role;

 RETURN (v_way, v_role);
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
------------------

-- Function: public.o2p_aggregate_line_relation(bigint)

-- DROP FUNCTION public.o2p_aggregate_line_relation(bigint);

CREATE OR REPLACE FUNCTION public.o2p_aggregate_line_relation(bigint)
  RETURNS geometry[] AS
$BODY$
DECLARE
  v_rel_id ALIAS for $1;
  v_way geometry[];
BEGIN

SELECT
  geom as route
FROM
  o2p_aggregate_relation(v_rel_id) INTO v_way;

 RETURN v_way;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
-------------------------------

-- Function: public.o2p_aggregate_polygon_relation(bigint)

-- DROP FUNCTION public.o2p_aggregate_polygon_relation(bigint);

CREATE OR REPLACE FUNCTION public.o2p_aggregate_polygon_relation(bigint)
  RETURNS geometry[] AS
$BODY$
DECLARE
  v_rel_id ALIAS for $1;
  v_polygons geometry[];
BEGIN

SELECT
  array_agg(ST_MakeValid(polygon)) polygons
FROM (
  SELECT
    ST_ForceRHR(CASE
      WHEN holes[1] IS NULL THEN ST_MakePolygon(shell)
      ELSE ST_MakePolygon(shell, holes)
    END) polygon
  FROM (
    SELECT
      outside.line AS shell,
      array_agg(inside.line) AS holes
    FROM (
      SELECT
        ST_MakeValid(geom) AS line,
        role
      FROM
        (
          SELECT
            unnest(geom) AS geom,
            unnest(role) AS role
          FROM
            o2p_aggregate_relation(v_rel_id)
        ) out_sub
      WHERE
        role != 'inner' AND
        ST_NPoints(geom) >= 4 AND
        ST_IsClosed(geom)
    ) outside LEFT OUTER JOIN (
      SELECT
        geom AS line,
        role
      FROM
        (
          SELECT
            unnest(geom) AS geom,
            unnest(role) AS role
          FROM
            o2p_aggregate_relation(v_rel_id)
        ) in_sub
      WHERE
        role = 'inner' AND
        ST_NPoints(geom) >= 4 AND
        ST_IsClosed(geom)
    ) inside ON ST_CONTAINS(ST_MakePolygon(outside.line), inside.line)
  GROUP BY
    outside.line) polys
) poly_array
INTO
  v_polygons;


RETURN v_polygons;
END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;


-- #NPS# ---------------------------------------------------------------------
-- nps render tables

-- Table: public.nps_render_point

-- DROP TABLE public.nps_render_point;

CREATE TABLE public.nps_render_point
(
  osm_id bigint NOT NULL,
  version integer,
  name text,
  type text, -- This is a calculated field. It calculates the point "type" from its "tags" field. It uses the o2p_get_type (true) function to perform the calculation.
  nps_type text, -- This is a calculated field. It calculates the polygon "type" from its "tags" field. It uses the o2p_get_type (false) function to perform the calculation.
  tags hstore, -- This contains all of the OpenStreetMap style tags associated with this point.
  rendered timestamp without time zone, -- This contains the time that this specific point was rendered. This is important for synchronizing the render tools.
  the_geom geometry, -- Contains the geometry for the point.
  z_order integer, -- Contains the display order of the points.  This is a calculated field, it is calclated from the "tags" field using the "o2p_calculate_zorder" function.
  unit_code text, -- The unit code of the park that contains this point
  CONSTRAINT osm_id PRIMARY KEY (osm_id)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE public.nps_render_point
  OWNER TO postgres;
COMMENT ON TABLE public.nps_render_point
  IS 'This table contains the most recent version of all visible points in order to be displayed on park tiles as well as be used in CartoDB.';
COMMENT ON COLUMN public.nps_render_point.type IS 'This is a calculated field. It calculates the point "type" from its "tags" field. It uses the o2p_get_type function to perform the calculation.';
COMMENT ON COLUMN public.nps_render_point.tags IS 'This contains all of the OpenStreetMap style tags associated with this point.';
COMMENT ON COLUMN public.nps_render_point.rendered IS 'This contains the time that this specific point was rendered. This is important for synchronizing the render tools.';
COMMENT ON COLUMN public.nps_render_point.the_geom IS 'Contains the geometry for the point.';
COMMENT ON COLUMN public.nps_render_point.z_order IS 'Contains the display order of the points.  This is a calculated field, it is calclated from the "tags" field using the "o2p_calculate_zorder" function.';
COMMENT ON COLUMN public.nps_render_point.unit_code IS 'The unit code of the park that contains this point';
-----------------------------------------------------------------------
-- nps render tables

-- Table: public.nps_render_polygon

-- DROP TABLE public.nps_render_polygon;

CREATE TABLE public.nps_render_polygon
(
  osm_id bigint NOT NULL,
  version integer,
  name text,
  type text, -- This is a calculated field. It calculates the polygon "type" from its "tags" field. It uses the o2p_get_type (true) function to perform the calculation.
  nps_type text, -- This is a calculated field. It calculates the polygon "type" from its "tags" field. It uses the o2p_get_type (false) function to perform the calculation.
  tags hstore, -- This contains all of the OpenStreetMap style tags associated with this polygon.
  rendered timestamp without time zone, -- This contains the time that this specific polygon was rendered. This is important for synchronizing the render tools.
  the_geom geometry, -- Contains the geometry for the polygon.
  z_order integer, -- Contains the display order of the polygons.  This is a calculated field, it is calclated from the "tags" field using the "o2p_calculate_zorder" function.
  unit_code text, -- The unit code of the park that contains this polygon
  CONSTRAINT nps_render_polygon_osm_id PRIMARY KEY (osm_id)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE public.nps_render_polygon
  OWNER TO postgres;
COMMENT ON TABLE public.nps_render_polygon
  IS 'This table contains the most recent version of all visible polygons in order to be displayed on park tiles as well as be used in CartoDB.';
COMMENT ON COLUMN public.nps_render_polygon.type IS 'This is a calculated field. It calculates the polygon "type" from its "tags" field. It uses the o2p_get_type function to perform the calculation.';
COMMENT ON COLUMN public.nps_render_polygon.tags IS 'This contains all of the OpenStreetMap style tags associated with this polygon.';
COMMENT ON COLUMN public.nps_render_polygon.rendered IS 'This contains the time that this specific polygon was rendered. This is important for synchronizing the render tools.';
COMMENT ON COLUMN public.nps_render_polygon.the_geom IS 'Contains the geometry for the polygon.';
COMMENT ON COLUMN public.nps_render_polygon.z_order IS 'Contains the display order of the polygons.  This is a calculated field, it is calclated from the "tags" field using the "o2p_calculate_zorder" function.';
COMMENT ON COLUMN public.nps_render_polygon.unit_code IS 'The unit code of the park that contains this polygon';


-----------------------------------------------------------------------
-- nps render tables

-- Table: public.nps_render_line

-- DROP TABLE public.nps_render_line;

CREATE TABLE public.nps_render_line
(
  osm_id bigint NOT NULL,
  version integer,
  name text,
  type text, -- This is a calculated field. It calculates the line "type" from its "tags" field. It uses the o2p_get_type (true) function to perform the calculation.
  nps_type text, -- This is a calculated field. It calculates the polygon "type" from its "tags" field. It uses the o2p_get_type (false) function to perform the calculation.
  tags hstore, -- This contains all of the OpenStreetMap style tags associated with this line.
  rendered timestamp without time zone, -- This contains the time that this specific line was rendered. This is important for synchronizing the render tools.
  the_geom geometry, -- Contains the geometry for the line.
  z_order integer, -- Contains the display order of the lines.  This is a calculated field, it is calclated from the "tags" field using the "o2p_calculate_zorder" function.
  unit_code text, -- The unit code of the park that contains this line
  CONSTRAINT nps_render_line_osm_id PRIMARY KEY (osm_id)
)
WITH (
  OIDS=FALSE
);
ALTER TABLE public.nps_render_line
  OWNER TO postgres;
COMMENT ON TABLE public.nps_render_line
  IS 'This table contains the most recent version of all visible lines in order to be displayed on park tiles as well as be used in CartoDB.';
COMMENT ON COLUMN public.nps_render_line.type IS 'This is a calculated field. It calculates the line "type" from its "tags" field. It uses the o2p_get_type function to perform the calculation.';
COMMENT ON COLUMN public.nps_render_line.tags IS 'This contains all of the OpenStreetMap style tags associated with this line.';
COMMENT ON COLUMN public.nps_render_line.rendered IS 'This contains the time that this specific line was rendered. This is important for synchronizing the render tools.';
COMMENT ON COLUMN public.nps_render_line.the_geom IS 'Contains the geometry for the line.';
COMMENT ON COLUMN public.nps_render_line.z_order IS 'Contains the display order of the lines.  This is a calculated field, it is calclated from the "tags" field using the "o2p_calculate_zorder" function.';
COMMENT ON COLUMN public.nps_render_line.unit_code IS 'The unit code of the park that contains this line';

--------------------------------------------------------
------------------------------
-- nps_render_log
------------------------------
-- This table is how we keep track of each process that was run
CREATE TABLE nps_render_log
(
  render_id bigint,
  task_name character varying(255),
  run_time timestamp without time zone
);
-----------------------------------------------------------------------

-- nps_change_log
------------------------------
-- Keeps track of changes to geometries so they can be removed from old maps
CREATE TABLE public.nps_change_log
(
  osm_id bigint,
  version integer,
  member_type character(1),
  way geometry,
  rendered timestamp without time zone,
  change_time timestamp without time zone
);
-----------------------------------------------------------------------


-- #NPS# -----------------------------------------------------------------
-- Rendering Views
--------------------------------
CREATE OR REPLACE VIEW public.nps_render_point_view AS 
SELECT
  "osm_id",
  "version",
  "name",
  "type",
  "nps_type",
  "tags", 
  "created", 
  "way",
  o2p_calculate_zorder("base"."nps_type", 'N') as "z_order",
  COALESCE("unit_code", (
    -- If the unit_code is null, try to join it up
    SELECT
      LOWER(unit_code)
    FROM
      park_unit_boundaries
    WHERE
      -- The projection for OSM is 900913, although we use 3857, and they are identical
      -- PostGIS requires a 'transform' between these two SRIDs when doing a comparison
      ST_Transform("base"."way", 3857) && "park_unit_boundaries"."the_geom" AND 
      ST_Contains("park_unit_boundaries"."the_geom",ST_Transform("base"."way", 3857))
    ORDER BY minzoompoly, area
    LIMIT 1
  )) AS "unit_code"
FROM (
  SELECT
    "nodes"."id" AS "osm_id",
    "nodes"."version" AS "version",
    "nodes"."tags" -> 'name'::text AS "name",
    o2p_get_type("tags", ARRAY['point'], true) AS "type",
    o2p_get_type("tags", ARRAY['point'], false) AS "nps_type",
    "tags" AS "tags",
    NOW()::timestamp without time zone AS "created",
    st_transform(nodes.geom, 900913) AS "way",
    "nodes"."tags" -> 'nps:unit_code'::text AS "unit_code"
  FROM
    "nodes"
  WHERE
    (
      SELECT
        array_length(array_agg("key"),1)
      FROM
        unnest(akeys(nodes.tags)) "key"
      WHERE
        "key" NOT LIKE 'nps:%'
    ) > 0
) "base"
WHERE
  "type" IS NOT NULL;
--------------------------------

--------------------------------
CREATE OR REPLACE VIEW public.nps_render_line_view AS 
SELECT
  "base"."osm_id",
  "base"."version",
  "base"."name",
  "base"."type",
  "base"."nps_type",
  "base"."tags", 
  "base"."created", 
  "base"."way",
  o2p_calculate_zorder("base"."nps_type", 'W') AS "z_order",
  COALESCE("base"."unit_code", (
    -- If the unit_code is null, try to join it up
    SELECT
      LOWER("park_unit_boundaries"."unit_code")
    FROM
      "park_unit_boundaries"
    WHERE
      -- The projection for OSM is 900913, although we use 3857, and they are identical
      -- PostGIS requires a 'transform' between these two SRIDs when doing a comparison
      ST_Transform("base"."way", 3857) && "park_unit_boundaries"."the_geom" AND 
      ST_Contains("park_unit_boundaries"."the_geom",ST_Transform("base"."way", 3857))
    ORDER BY "park_unit_boundaries"."minzoompoly", "park_unit_boundaries"."area"
    LIMIT 1
  )) AS "unit_code"
FROM (
  SELECT
    "ways"."id" AS "osm_id",
    "ways"."version" AS "version",
    "ways"."tags" -> 'name'::text AS "name",
    o2p_get_type("ways"."tags", ARRAY['line'], true) AS "type",
    o2p_get_type("ways"."tags", ARRAY['line'], false) AS "nps_type",
    "ways"."tags" AS "tags",
    NOW()::timestamp without time zone AS "created",
    ST_Transform(o2p_calculate_nodes_to_line(ways.nodes), 900913) AS "way",
    "ways"."tags" -> 'nps:unit_code'::text AS "unit_code"
  FROM
    "ways"
  WHERE
    NOT (EXISTS (
      SELECT
        1
      FROM
        relation_members JOIN relations 
        ON "relation_members"."relation_id" = "relations"."id"
      WHERE "relation_members"."member_id" = "ways"."id" AND
        UPPER("relation_members"."member_type") = 'W'::bpchar AND
        ("relations"."tags" -> 'type'::text) = 'route'::text
    )) AND
    (
      SELECT
        ARRAY_LENGTH(array_agg("key"),1)
      FROM
        UNNEST(AKEYS("ways"."tags")) "key"
      WHERE
        "key" NOT LIKE 'nps:%'
    ) > 0
  UNION ALL
  SELECT
    "rel_line"."osm_id" AS "osm_id",
    "rel_line"."version" AS "version",
    "rel_line"."tags" -> 'name'::text AS "name",
    o2p_get_type("rel_line"."tags", ARRAY['line'], true) AS "type",
    o2p_get_type("rel_line"."tags", ARRAY['line'], false) AS "nps_type",
    "rel_line"."tags" AS "tags",
    NOW()::timestamp without time zone AS "created",
    rel_line.way AS "way",
    "rel_line"."tags" -> 'nps:unit_code'::text AS "unit_code"
  FROM (
    SELECT
      "relation_members"."relation_id" * (-1) AS "osm_id",
      "relations"."version",
      "relations"."tags",
      ST_Transform(ST_Union(o2p_aggregate_line_relation("relation_members"."relation_id")), 900913) AS "way"
      FROM
        "ways"
        JOIN "relation_members" ON "ways"."id" = "relation_members"."member_id"
        JOIN "relations" ON "relation_members"."relation_id" = "relations"."id"
      WHERE
        (
          SELECT
            ARRAY_LENGTH(ARRAY_AGG("key"),1)
          FROM
            UNNEST(AKEYS("relations"."tags")) "key"
          WHERE
            "key" NOT LIKE 'nps:%'
        ) > 0 AND
        exist(relations.tags, 'type'::text)
        GROUP BY
          "relation_members"."relation_id",
          "relations"."version",
          "relations"."tags"
      ) rel_line
) "base"
WHERE
  "base"."type" IS NOT NULL;
--------------------------------

--------------------------------
CREATE OR REPLACE VIEW public.nps_render_polygon_view AS 
SELECT
  "base"."osm_id",
  "base"."version",
  "base"."name",
  "base"."type",
  "base"."nps_type",
  "base"."tags", 
  "base"."created", 
  "base"."way",
  o2p_calculate_zorder("base"."nps_type", 'W') AS "z_order",
  COALESCE("base"."unit_code", (
    -- If the unit_code is null, try to join it up
    SELECT
      LOWER("park_unit_boundaries"."unit_code")
    FROM
      "park_unit_boundaries"
    WHERE
      -- The projection for OSM is 900913, although we use 3857, and they are identical
      -- PostGIS requires a 'transform' between these two SRIDs when doing a comparison
      ST_Transform("base"."way", 3857) && "park_unit_boundaries"."the_geom" AND 
      ST_Contains("park_unit_boundaries"."the_geom",ST_Transform("base"."way", 3857))
    ORDER BY "park_unit_boundaries"."minzoompoly", "park_unit_boundaries"."area"
    LIMIT 1
  )) AS "unit_code"
FROM (
  SELECT
    "ways"."id" AS "osm_id",
    "ways"."version" AS "version",
    "ways"."tags" -> 'name'::text AS "name",
    o2p_get_type("ways"."tags", ARRAY['area'], true) AS "type",
    o2p_get_type("ways"."tags", ARRAY['area'], false) AS "nps_type",
    "ways"."tags" AS "tags",
    NOW()::timestamp without time zone AS "created",
    ST_MakePolygon(ST_Transform(o2p_calculate_nodes_to_line("ways"."nodes"), 900913)) AS way,
    "ways"."tags" -> 'nps:unit_code'::text AS "unit_code"
  FROM
    "ways"
  WHERE
    ARRAY_LENGTH("ways"."nodes", 1) >= 4 AND
    NOT (EXISTS (
      SELECT
        1
      FROM
        relation_members JOIN relations 
        ON "relation_members"."relation_id" = "relations"."id"
      WHERE "relation_members"."member_id" = "ways"."id" AND
        UPPER("relation_members"."member_type") = 'W'::bpchar AND
          (
            ("relations"."tags" -> 'type'::text) = 'multipolygon'::text OR
            ("relations"."tags" -> 'type'::text) = 'boundary'::text OR
            ("relations"."tags" -> 'type'::text) = 'route'::text
          )
    )) AND
    (
      SELECT
        ARRAY_LENGTH(array_agg("key"),1)
      FROM
        UNNEST(AKEYS("ways"."tags")) "key"
      WHERE
        "key" NOT LIKE 'nps:%'
    ) > 0 AND
    ST_IsClosed(o2p_calculate_nodes_to_line("ways"."nodes"))
  UNION ALL
  SELECT
    "rel_poly"."osm_id" AS "osm_id",
    "rel_poly"."version" AS "version",
    "rel_poly"."tags" -> 'name'::text AS "name",
    o2p_get_type("rel_poly"."tags", ARRAY['area'], true) AS "type",
    o2p_get_type("rel_poly"."tags", ARRAY['area'], false) AS "nps_type",
    "rel_poly"."tags" AS "tags",
    NOW()::timestamp without time zone AS "created",
    rel_poly.way AS "way",
    "rel_poly"."tags" -> 'nps:unit_code'::text AS "unit_code"
  FROM (
    SELECT
      "relation_members"."relation_id" * (-1) AS "osm_id",
      "relations"."version" AS "version",
      "relations"."tags",
      ST_Transform(ST_Union(o2p_aggregate_polygon_relation("relation_members"."relation_id")), 900913) AS "way"
    FROM
      "ways"
        JOIN "relation_members" ON "ways"."id" = "relation_members"."member_id"
        JOIN "relations" ON "relation_members"."relation_id" = "relations"."id"
    WHERE
      (
        SELECT
          ARRAY_LENGTH(ARRAY_AGG("key"),1)
        FROM
          UNNEST(AKEYS("relations"."tags")) "key"
        WHERE
          "key" NOT LIKE 'nps:%'
      ) > 0 AND
      ARRAY_LENGTH("ways"."nodes", 1) >= 4 AND
      ST_IsClosed(o2p_calculate_nodes_to_line(ways.nodes)) AND
      exist(relations.tags, 'type'::text) AND
      (
        (relations.tags -> 'type'::text) = 'multipolygon'::text OR
        (relations.tags -> 'type'::text) = 'boundary'::text OR
        (relations.tags -> 'type'::text) = 'route'::text
      )
      GROUP BY
        "relation_members"."relation_id",
        "relations"."version",
        "relations"."tags"
  ) rel_poly
) "base"
WHERE
  "base"."type" IS NOT NULL;


----------------------------------------

-- Function: public.o2p_render_element(bigint, character)

-- DROP FUNCTION public.o2p_render_element(bigint, character);

CREATE OR REPLACE FUNCTION public.o2p_render_element(bigint, character)
  RETURNS boolean AS
$BODY$
  DECLARE
    v_id ALIAS FOR $1;
    v_member_type ALIAS FOR $2;
    v_rel_id BIGINT;
  BEGIN
  
  -- Add any information that will be deleting / changing
  -- to the change log, which is used to keep the renderers synchronized
    IF UPPER(v_member_type) = 'N' THEN
    -- Nodes have different OSM_IDs than ways, so we do them separently
      INSERT INTO nps_change_log (
        SELECT
          v_id AS "osm_id",
          MIN("nps_rendered"."version") AS "version",
          v_member_type AS "member_type",
          ST_UNION("nps_rendered"."the_geom") AS "way",
          MIN("nps_rendered"."rendered") AS "created",
          NOW()::timestamp without time zone AS "change_time"
        FROM (
           SELECT
             "osm_id",
             "version",
             "the_geom",
             "rendered"
           FROM
             "nps_render_point") AS "nps_rendered"
        WHERE
          "osm_id" = v_id
      );

      DELETE FROM "nps_render_point" WHERE osm_id = v_id;
      INSERT INTO "nps_render_point" (
        SELECT
          "osm_id" AS "osm_id",
          "version" AS "version",
          "name" AS "name",
          "type" AS "type",
          "nps_type" AS "nps_type",
          "tags" AS "tags",
          "created" AS "rendered",
          "way" AS "the_geom",
          "z_order" AS "z_order",
          "unit_code" AS "unit_code"
        FROM "nps_render_point_view"
        WHERE "osm_id" = v_id
      );
    ELSE
      -- Nodes have different OSM_IDs than ways, so we do them separently
      -- relations also have different ids, but we make them negative so they can fit in the same namespace
      INSERT INTO nps_change_log (
      SELECT
        v_id AS "osm_id",
        MIN("nps_rendered"."version") AS "version",
        v_member_type AS "member_type",
        ST_UNION("nps_rendered"."the_geom") AS "way",
        MIN("nps_rendered"."rendered") AS "created",
        NOW()::timestamp without time zone AS "change_time"
      FROM (
         SELECT
           "osm_id",
           "version",
           "the_geom",
           "rendered"
         FROM
           "nps_render_polygon"
         UNION ALL
         SELECT
           "osm_id",
           "version",
           "the_geom",
           "rendered"
         FROM
           "nps_render_line") AS "nps_rendered"
      WHERE
        "osm_id" = v_id
    );

      DELETE FROM "nps_render_polygon" WHERE "osm_id" = v_id;
      INSERT INTO "nps_render_polygon" (
        SELECT
          "osm_id" AS "osm_id",
          "version" AS "version",
          "name" AS "name",
          "type" AS "type",
          "nps_type" AS "nps_type",
          "tags" AS "tags",
          "created" AS "rendered",
          "way" AS "the_geom",
          "z_order" AS "z_order",
          "unit_code" AS "unit_code"
        FROM "nps_render_polygon_view"
        WHERE "osm_id" = v_id
      );

      DELETE FROM "nps_render_line" WHERE osm_id = v_id;
      INSERT INTO "nps_render_line" (
        SELECT
          "osm_id" AS "osm_id",
          "version" AS "version",
          "name" AS "name",
          "type" AS "type",
          "nps_type" AS "nps_type",
          "tags" AS "tags",
          "created" AS "rendered",
          "way" AS "the_geom",
          "z_order" AS "z_order",
          "unit_code" AS "unit_code"
        FROM "nps_render_line_view"
        WHERE "osm_id" = v_id
      );
    END IF;

    RETURN true;
  END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
--------------------------------
-- #NPS#
---------------------------
-- Foreign Data
---------------------------
CREATE EXTENSION postgres_fdw;
CREATE SERVER places_prod FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'localhost', port '5432', dbname 'places_prod');
CREATE USER MAPPING FOR PUBLIC SERVER places_prod OPTIONS (user 'places_prod', password 'places_prod');

--DROP FOREIGN TABLE api_changesets;
CREATE FOREIGN TABLE api_changesets (id bigint, closed_at timestamp without time zone) SERVER places_prod OPTIONS (table_name 'changesets');
--DROP FOREIGN TABLE api_nodes;
CREATE FOREIGN TABLE api_nodes (id bigint, visible boolean, version bigint, changeset bigint, "timestamp" timestamp without time zone, "user" text, uid bigint, lat double precision, lon double precision, tag JSON) SERVER places_prod OPTIONS (table_name 'api_current_nodes');
--DROP FOREIGN TABLE api_ways;
CREATE FOREIGN TABLE api_ways (id bigint, visible boolean, version bigint, changeset bigint, "timestamp" timestamp without time zone, "user" text, "uid" bigint, nd JSON, tag JSON)  SERVER places_prod OPTIONS (table_name 'api_current_ways');
--DROP FOREIGN TABLE api_relations;
CREATE FOREIGN TABLE api_relations (id bigint, visible boolean, version bigint, changeset bigint, "timestamp" timestamp without time zone, "user" text, "uid" bigint, member JSON, tag JSON) SERVER places_prod OPTIONS (table_name 'api_current_relations');
--DROP FOREIGN TABLE api_users;
CREATE FOREIGN TABLE api_users (email character varying (255), id bigint, display_name character varying (255)) SERVER places_prod OPTIONS (table_name 'users');

--------------------------------
-- #NPS# ------
-----------------------
-- Render Functions
--DROP FUNCTION pgs_upsert_node(bigint, double precision, double precision, bigint, boolean, timestamp without time zone, json, bigint, bigint);
CREATE OR REPLACE FUNCTION pgs_upsert_node(
  bigint,
  double precision,
  double precision,
  bigint,
  boolean,
  timestamp without time zone,
  json,
  bigint,
  bigint
) RETURNS boolean AS $pgs_upsert_node$
  DECLARE
    v_id ALIAS FOR $1;
    v_lat ALIAS FOR $2;
    v_lon ALIAS FOR $3;
    v_changeset ALIAS FOR $4;
    v_visible ALIAS FOR $5;
    v_timestamp ALIAS FOR $6;
    v_tags ALIAS FOR $7;
    v_version ALIAS FOR $8;
    v_userid ALIAS FOR $9;
    v_X boolean;
    BEGIN
  -- Delete the current nodes and tags
    DELETE from nodes where id = v_id;

    IF v_visible THEN
      INSERT INTO
        nodes (
          id,
          version,
          user_id,
          tstamp,
          changeset_id,
          tags,
          geom
        ) VALUES (
          v_id,
          v_version,
          v_userid,
          v_timestamp,
          v_changeset,
          (select hstore(array_agg(k), array_agg(v)) from json_populate_recordset(null::new_hstore,v_tags)),
          ST_SetSRID(ST_MakePoint(v_lon, v_lat),4326)
        );
    END IF;
    
    -- This is the default OSM style, we will use the NPS style(s) instead
    SELECT o2p_render_element(v_id, 'N') into v_X;

    RETURN v_X;
    END;
$pgs_upsert_node$ LANGUAGE plpgsql;


-- ----------------------------------------
--DROP FUNCTION pgs_upsert_way(bigint, bigint, boolean, timestamp without time zone, json, json, bigint, bigint);
CREATE OR REPLACE FUNCTION pgs_upsert_way(
  bigint,
  bigint,
  boolean,
  timestamp without time zone,
  json,
  json,
  bigint,
  bigint
) RETURNS boolean AS $pgs_upsert_way$
  DECLARE
    v_id ALIAS FOR $1;
    v_changeset ALIAS FOR $2;
    v_visible ALIAS FOR $3;
    v_timestamp ALIAS FOR $4;
    v_nodes ALIAS FOR $5;
    v_tags ALIAS FOR $6;
    v_version ALIAS FOR $7;
    v_user_id ALIAS FOR $8;
    v_X boolean;
  BEGIN 

  -- Delete the current way nodes and tags
    DELETE from way_nodes where way_id = v_id;
    DELETE from ways where id = v_id;

    IF v_visible THEN
      INSERT INTO
        ways (
          id,
          version,
          user_id,
          tstamp,
          changeset_id,
          tags,
          nodes
        ) VALUES (
          v_id,
          v_version,
          v_user_id,
          v_timestamp,
          v_changeset,
          (select hstore(array_agg(k), array_agg(v)) from json_populate_recordset(null::new_hstore,v_tags)),
          (SELECT array_agg(node_id) FROM json_populate_recordset(null::way_nodes, v_nodes))
        );    
    
        -- Associated Nodes
        INSERT INTO
         way_nodes (
         SELECT
           v_id AS way_id,
           node_id as node_id,
           sequence_id as sequence_id
         FROM
           json_populate_recordset(
             null::way_nodes,
             v_nodes
           )
         );
      END IF;
      
      SELECT o2p_render_element(v_id, 'W') into v_X;

    RETURN v_X;
    END;
$pgs_upsert_way$ LANGUAGE plpgsql;

-- ------------------------------------------
--DROP FUNCTION pgs_upsert_relation(bigint, bigint, boolean, json, json, timestamp without time zone, bigint, bigint);
CREATE OR REPLACE FUNCTION pgs_upsert_relation(
  bigint,
  bigint,
  boolean,
  json,
  json,
  timestamp without time zone,
  bigint,
  bigint
) RETURNS boolean AS $pgs_upsert_relation$
  DECLARE
    v_id ALIAS FOR $1;
    v_changeset ALIAS FOR $2;
    v_visible ALIAS FOR $3;
    v_members ALIAS FOR $4;
    v_tags ALIAS FOR $5;
    v_timestamp ALIAS FOR $6;
    v_version ALIAS FOR $7;
    v_user_id ALIAS FOR $8;
    v_X boolean;
  BEGIN

  -- Delete the current way nodes and tags
    DELETE from relation_members where relation_id = v_id;
    DELETE from relations where id = v_id;

    IF v_visible THEN
      INSERT INTO
        relations (
          id,
          version,
          user_id,
          tstamp,
          changeset_id,
          tags
        ) VALUES (
          v_id,
          v_version,
          v_user_id,
          v_timestamp,
          v_changeset,
          (select hstore(array_agg(k), array_agg(v)) from json_populate_recordset(null::new_hstore,v_tags))
        );    

      -- Associated Members
      INSERT INTO
        relation_members (
          SELECT
             v_id AS relation_id,
             member_id as member_id,
             member_type::character(1) as member_type,
             member_role as member_role,
             sequence_id as sequence_id
        FROM
           json_populate_recordset(
           null::new_relation_members,
           v_members
         )
        );
    END IF;
    
    SELECT o2p_render_element(v_id, 'R') into v_X;

    RETURN v_X;
    END;
$pgs_upsert_relation$ LANGUAGE plpgsql;

-- ------------------------------------------
--DROP FUNCTION pgs_update();
CREATE OR REPLACE FUNCTION pgs_update()
RETURNS bigint AS $pgs_update$
  DECLARE
    v_last_changeset bigint;
    v_changes bigint;
  BEGIN

    SELECT MAX(changeset_id) AS last_changeset FROM
    (
      SELECT changeset_id FROM nodes
      UNION ALL
      SELECT changeset_id FROM ways
      UNION ALL
      SELECT changeset_id FROM relations
    ) all_updates INTO v_last_changeset;

    SELECT pgs_update(v_last_changeset) INTO v_changes;

    RETURN v_changes;
    END;
$pgs_update$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pgs_update(bigint)
RETURNS bigint AS $pgs_update$
  DECLARE
    v_last_changeset ALIAS for $1;
    v_changes bigint;
  BEGIN
  
    SELECT count(*) FROM (
    SELECT pgs_upsert_node(id, lat, lon, changeset, visible, timestamp, tag, version, uid) FROM api_nodes WHERE changeset > v_last_changeset
    UNION ALL
    SELECT pgs_upsert_way(id, changeset, visible, timestamp, nd, tag, version, uid) FROM api_ways WHERE changeset > v_last_changeset
    UNION ALL
    SELECT pgs_upsert_relation(id, changeset, visible, member, tag, timestamp, version, uid) FROM api_relations WHERE changeset > v_last_changeset)
    changes INTO v_changes;

    -- Update the users
    INSERT INTO users SELECT id, display_name AS name FROM api_users WHERE id NOT IN (SELECT id FROM users);

    RETURN v_changes;
    END;
$pgs_update$ LANGUAGE plpgsql;

-----------------------------
-- #NPS# --------
-----------------------------
-- Rendering views

-- CartoDB
CREATE OR REPLACE VIEW public.nps_cartodb_line_view AS 
 SELECT nps_render_line.osm_id AS cartodb_id,
    nps_render_line.version,
    nps_render_line.tags -> 'name'::text AS name,
    nps_render_line.tags -> 'nps:places_id'::text AS places_id,
    nps_render_line.unit_code,
    nps_render_line.nps_type AS type,
    nps_render_line.tags::json::text AS tags,
    nps_render_line.the_geom
   FROM nps_render_line;

CREATE OR REPLACE VIEW public.nps_cartodb_point_view AS 
 SELECT nps_render_point.osm_id AS cartodb_id,
    nps_render_point.version,
    nps_render_point.tags -> 'name'::text AS name,
    nps_render_point.tags -> 'nps:places_id'::text AS places_id,
    nps_render_point.unit_code,
    nps_render_point.nps_type AS type,
    nps_render_point.tags::json::text AS tags,
    nps_render_point.the_geom
   FROM nps_render_point;

CREATE OR REPLACE VIEW public.nps_cartodb_polygon_view AS 
 SELECT nps_render_polygon.osm_id AS cartodb_id,
    nps_render_polygon.version,
    nps_render_polygon.tags -> 'name'::text AS name,
    nps_render_polygon.tags -> 'nps:places_id'::text AS places_id,
    nps_render_polygon.unit_code,
    nps_render_polygon.nps_type AS type,
    nps_render_polygon.tags::json::text AS tags,
    nps_render_polygon.the_geom
   FROM nps_render_polygon;

