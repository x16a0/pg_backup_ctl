.PHONY=distri
PROJECT=pg_backup_ctl
FILES=pg_backup_ctl README
PG_BACKUP_CTL_VERSION=0.2


distribution: ${FILES}
	mkdir -p ${PROJECT}-${PG_BACKUP_CTL_VERSION}
	cp -v ${FILES} ${PROJECT}-${PG_BACKUP_CTL_VERSION}
	tar -cvjf ${PROJECT}-${PG_BACKUP_CTL_VERSION}.tar.bz2 ${PROJECT}-${PG_BACKUP_CTL_VERSION}
	rm -rf ${PROJECT}-${PG_BACKUP_CTL_VERSION}

clean:
	rm -f *~
	rm -f *.*~
	rm -rf ${PROJECT}-${PG_BACKUP_CTL_VERSION}.tar.bz2