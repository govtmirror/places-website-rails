require "migrate"

class ChangeColumnTagsToText < ActiveRecord::Migration
  def up
      change_column :node_tags, :k, :text
      change_column :node_tags, :v, :text
      change_column :changeset_tags, :k, :text
      change_column :changeset_tags, :v, :text
      change_column :relation_tags, :k, :text
      change_column :relation_tags, :v, :text
      change_column :way_tags, :k, :text
      change_column :way_tags, :v, :text
      change_column :current_node_tags, :k, :text
      change_column :current_node_tags, :v, :text
      change_column :current_way_tags, :k, :text
      change_column :current_way_tags, :v, :text
      change_column :current_relation_tags, :k, :text
      change_column :current_relation_tags, :v, :text
  end

  def down
      change_column :node_tags, :k, :string
      change_column :node_tags, :v, :string
      change_column :changeset_tags, :k, :string
      change_column :changeset_tags, :v, :string
      change_column :relation_tags, :k, :string
      change_column :relation_tags, :v, :string
      change_column :way_tags, :k, :string
      change_column :way_tags, :v, :string
      change_column :current_node_tags, :k, :string
      change_column :current_node_tags, :v, :string
      change_column :current_way_tags, :k, :string
      change_column :current_way_tags, :v, :string
      change_column :current_relation_tags, :k, :string
      change_column :current_relation_tags, :v, :string
  end
end
