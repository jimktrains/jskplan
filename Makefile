all: clean install test

PSQL_OPTS=-v ON_ERROR_STOP=1
DB=jskplan

install:
	psql ${PSQL_OPTS} -f schema.sql ${DB}

test:
	psql ${PSQL_OPTS} -f test.sql ${DB}

clean:
	dropdb ${DB}
	createdb ${DB}

