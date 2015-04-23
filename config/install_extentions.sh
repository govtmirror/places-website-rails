usernames=`grep "username:" database.yml | perl -p -e 's|.*username: (.+)|\1|g'`
databases=`grep "database:" database.yml | perl -p -e 's|.*database: (.+)|\1|g'`

if [ $1 = 'makeUsers']; then
  for user in $usernames; do
    createuser -s $user
    alter user $user with password '$user';
  done
elif [ $1 = 'createDbExtentions']; then
  for database in $databases; do
    psql -d $database -c "CREATE EXTENSION btree_gist"
    psql -d $database -c "CREATE FUNCTION maptile_for_point(int8, int8, int4) RETURNS int4 AS '`pwd`/../db/functions/libpgosm', 'maptile_for_point' LANGUAGE C STRICT"
    psql -d $database -c "CREATE FUNCTION tile_for_point(int4, int4) RETURNS int8 AS '`pwd`/../db/functions/libpgosm', 'tile_for_point' LANGUAGE C STRICT"
    psql -d $database -c "CREATE FUNCTION xid_to_int4(xid) RETURNS int4 AS '`pwd`/../db/functions/libpgosm', 'xid_to_int4' LANGUAGE C STRICT"
  done
fi
