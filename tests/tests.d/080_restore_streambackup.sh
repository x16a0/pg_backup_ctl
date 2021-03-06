min_version "9.2"
assert 030_streambackup
local md5="$(assert pgdo "psql -XqtA -f check.sql")"
assert pgdo "pg_ctlcluster ${current_version} ${test_cluster} stop"
assert do_clean_datadir
assert pgbc -D ${test_datadir} restore $(ls ${test_archive_dir}/base/)
assert pgdo "pg_ctlcluster ${current_version} ${test_cluster} start"
assert test "${md5}" == "$(assert pgdo "psql -XqtA -f check.sql")"
