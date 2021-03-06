Transaction Log Archival Backup
===============================

``pg_backup_ctl`` is a tool to simplify the steps needed to make a full
transaction log archival backup of PostgreSQL clusters. All steps performed by
this script can also be done manually. See
http://www.postgresql.org/docs/current/static/continuous-archiving.html for
details. Furthermore, this script implements several functions to prepare for
backups using LVM snapshots.

This scripts supports PostgreSQL 8.3 and above.

Theory
------

Broadly speaking, the backup process involves the following phases:

1. Designate room for the archive.

    For the purpose of this document we will assume the location
    /var/lib/pgsql/backup.  Naturally, this backup location should be as
    far away as possible from the data area at /var/lib/pgsql/data to
    ensure they are not destroyed together.  (If you have them both on the
    Netapp Filer, that is OK.)  Do not put the backup inside of the data
    area; that will make everything terribly complicated.

2. Configure the archival.

    This involves changing the server configuration file parameter
    archive_command to the shell command done to do the setup.

3. Do a base backup.

    3.1 File based base backup

    A base backup is a tarball (or some other copy) of the data area taken
    from the file system while the system is in special backup mode.  (No
    file system snapshot functionality is required for this.)

    3.2 LVM snapshot based base backup

    ``pg_backup_ctl`` supports base backups using LVM snapshots.
    This is done by the lvmbasebackup command. This requires the -M, -N, -n and
    -L arguments to ``pg_backup_ctl``. For example, to perform a base backup using
    the LVM snapshot ``pg_backup`` on the logical volume ``/dev/backup/pg_backup`` with
    a snapshot size of 5GB, you can do:

        $ pg_backup_ctl -A /backup/archive/ -D /var/lib/postgresql/ \
            -M /dev/backup/pg_backup -n pg_backup -L 5G -N postgresql lvmbasebackup

    Please note the -N parameter. This specifies the data directory of your 
    PostgreSQL cluster relatively to the mounted LVM snapshot. ``pg_backup_ctl``
    will use the directory /backup/archive/lvm_snapshot as the mount directory.
    Since ``pg_backup_ctl`` runs as user postgres in normal environments, you want
    to add sudo execution privileges for postgres to the following commands:

    - lvcreate, lvremove, lvdisplay
    - mount, umount

    3.3 External backup software support

    With release 0.3.x ``pg_backup_ctl`` also supports integration with external backup
    software and filesystem snapshots (Linux only).

    The normal task to perform such a backup is
    as follows:

    - Prepare the database snapshot and LVM snapshot:

            $ pg_backup_ctl -A ARCHIVEDIR LVM-OPTIONS lvm-createsnapshot

    - Perform the backup with your external backup utility, but CAUTION:
      The filesystem snapshot is automatically mounted in ``ARCHIVEDIR/lvm_snapshot``!
      NEVER EVER perform the backup from the PGDATA directory directly!

    - After finishing the filesystem level backup, remove the LVM snapshot
      from the system:

            $ pg_backup_ctl -A ARCHIVEDIR LVM-OPTIONS remove-lvmsnapshot

    We also recommend to implement a monitoring check for failed LVM snapshots.

4. Save the current log segment.

    Log segments are only archived when they are full (16 MB).  In case
    the data area is lost (hardware failure etc.), data in segments that
    were not archived is lost (i.e., the last few transactions before the
    incident).  If the load on the system is such that segments fill
    slowly, it is advisable to specially copy the currently active
    segments to a safe place using a cron job.

5. Clean up.

    After each base backup, log segments archived before that base backup
    can be discarded to free the disk space.  The exact conditions under
    which this can be done are explained in the documentation.


Practice
--------

To simplify this process, the attached script ``pg_backup_ctl`` automates
these tasks.  Just copy the script to a convenient place (perhaps
/usr/local/bin).  The script should be run as the postgres user.  The
general usage is:

    $ pg_backup_ctl -h HOST -p PORT -U USER -A ARCHIVEDIR COMMAND

The host, port, and user name can usually be omitted, and we don't
include them in the examples below.  Details on the command follow.

1. Although not officially required, the backup process that we
    propose uses the following subdirectories for various parts of the
    backup to make things clearer:

    - base/ -- base backups
    - current/ -- backup of the currently active log segment
    - log/ -- backup of the completed log segments

2. To set up the archival process, run the following command:

        $ pg_backup_ctl -A /var/lib/pgsql/backup setup

    This adjusts the server configuration file as required and reloads the
    server configuration.  However, since PostgreSQL 8.3 the script needs to set
    the archive_mode explicitly to on, forcing the administrator to restart the
    PostgreSQL instance (if required). After a restart (assuming there is database
    activity), you should be seeing files appearing in
    /var/lib/pgsql/backup/log.

3. To do a base backup, run the following command:

        $ pg_backup_ctl -A /var/lib/pgsql/backup basebackup

    This will put the base backup at
    /var/lib/pgsql/backup/base/basebackup-$timestamp.tar.gz.

    You should run this command from a cron job (mind the postgres user)
    once a night.  (Once a week or other intervals are also conceivable
    but will lead to huge recovery times for your data volume.)

    You could replace this step by taking a file system snapshot.  This
    might save space and time but would otherwise be functionally
    equivalent.  You can also alter the script accordingly.  Look into the
    line that calls the tar program.

3. To copy the current log segment(s), run the following command:

        $ pg_backup_ctl -A /var/lib/pgsql/backup currentbackup

    This will copy the required files into /var/lib/pgsql/backup/current/
    and remove any older "current" files.

    One typically runs this command from a cron job once a minute (or
    whatever the desired backup frequency).  It is quite possible that
    your data volume will cause log segments to fill up on the order of
    minutes anyway, so this step can then be omitted.

4. To clean up, run the following command:

        $ pg_backup_ctl -A /var/lib/pgsql/backup cleanup

    This will remove files from /var/lib/pgsql/backup/log/ that are no
    longer needed.  This can be run as often as you like, but it is best
    run from a cron job after the base backup (for best effect not
    immediately after, perhaps one hour later).

    This will only clean up old log segments.  Old base backups have to be
    removed manually.


Recovery
--------

Starting with ``pg_backup_ctl`` 0.6 you have the choice to use the
restore command to recover a base backup into an empty directory. This
will create a recovery.conf and a restored base backup suitable
to be recovered immediately by starting a PostgreSQL server using
this directory. For example

    $ pg_backup_ctl -A /var/lib/pgsql/backup ls+
    Basebackup Filename              	Size	Required WAL             Available
    --------------------------------------------------------------------------------
    streaming_backup_2014-01-13T1133 	3.0M	00000001000000000000002F YES
    streaming_backup_2014-01-13T1132 	3.0M	00000001000000000000002D YES
    streaming_backup_2014-01-09T1802 	3.0M	00000001000000000000002B YES
    basebackup_2014-01-09T1802.tar.gz	3.0M	00000001000000000000002A YES
    --------------------------------------------------------------------------------
    Total size occupied by 8 WAL segments in archive: 129M

There's one base backup available, so we are going to restore this:

    $ pg_backup_ctl -A /var/lib/pgsql/backup -D /recovery/pgsql restore basebackup_2014-01-09T1802.tar.gz

The -D parameter is mandatory when using the restore command. You cannot
use a directory which contains any objects, ``pg_backup_ctl`` will refuse to
do the restore.

It is still possible to do the recovery process completely manually.
The recovery process is detailed in the documentation.  Broadly
speaking it works like this:

1. Stop the server.

2. Move the current data directory to a safe location.  (If the
current data directory was lost, omit this.)

3. Delete everything in the data directory (if you have not moved it
away already).

4. Restore the base backup (that is, untar the base backup tarball to
where the data directory that you just removed was).

5. Create the directories ``pg_xlog/`` and ``pg_xlog/archive_status/`` in the
data directory that you just untarred.  (If you do not use our
provided tar-based base backup, make sure that these directories now
exist and are empty.)

6. Copy the current log segments from /var/lib/pgsql/backup/current/
to ``pg_xlog``.  If you moved the current data directory away in step 2,
you will also have the current log segments in that directory's
``pg_xlog`` subdirectory.  It may be that these are more up to date then
those in backup/current/, depending on how often that cron job runs.
You need to exercise judgement here depending on the kind of crash or
incident that you want to recover from.

7. Create a file recovery.conf in the new data directory with the
    following contents:

        restore_command = 'cp /var/lib/pgsql/backup/log/%f "%p"'

    Other possible settings to do point-in-time recovery (as opposed to
    recovering to the very end of the log, as we're doing now) are
    detailed in the documentation at
    http://www.postgresql.org/docs/current/static/recovery-target-settings.html

8. Start the server.

9. Connect to the server and check out whether the database is in the
state you like.


Naturally, this process should be tested and a couple of people should
be trained so that this process can be performed rapidly in case of a
problem.  Please let us know if we can assist you further on this
matter.

Caveats
-------

``pg_backup_ctl`` internally protects itself against concurrent execution
with the flock command line tool. This places a lock file into the
archive directory, which will hold an exclusive lock on it to prevent
another ``pg_backup_ctl`` to concurrently modify the archive. This doesn't
work on network filesystems like SMBFS or CIFS, especially when mounted
from a Windows(tm) server. In this case you should use the -l option
to place the lockfile into a directory on a local filesystem.

Older distributions doesn't have the flock command line tool, but it's
possible to just comment out the locking subscripts.

The base backup command currently doesn't support tablespaces. Use streaming
base backups instead, which has full support for tablespaces. This requires
PostgreSQL 9.1 and above since the ``pg_basebackup`` tool is not available in
older releases.

If you restore a streaming base backup with tablespaces, you should be aware that
the default operation mode restores the tablespace into the original directories.
This doesn't work if you are going to restore the backup on the same machine and
will cause the restore command to abort with an error, telling you that the
target directory isn't empty (obviously, since it already contains the original
tablespace data). Use the -T option instead, which will force ``pg_backup_ctl``
to use an alternative tablespace restore location. However, this substitutes
all tablespace directories to be located in a single top level directory, even
if you have used different directories in your source installation. The tablespaces
will be adjusted and have a layout and naming according to their OID.
