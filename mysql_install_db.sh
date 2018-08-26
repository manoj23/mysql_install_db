#!/usr/bin/env bash

REQUIRED_PROGRAMS="jq mysql mysqld_safe mysql_install_db mysql_secure_installation"

# Copied from mysql_secure_installation
__basic_single_escape()
{
	# shellcheck disable=SC2001
	echo "$1" | sed 's/\(['"'"'\]\)/\\\1/g'
}

parse_args()
{
	if [ $# -lt 3 ]; then
		echo "expect at least 2 arguments, Bye!"
		exit 1
	fi

	if [ ! -e "$2" ]; then
		echo "$2 does not exist, Bye!"
		exit 1
	fi

	if [ ! -r "$2" ]; then
		echo "$2 cannot be read, Bye!"
		exit 1
	fi

	if [ ! -e "$3" ]; then
		echo "$3 does not exist, Bye!"
		exit 1
	fi

	if [ ! -d "$3" ]; then
		echo "$3 is not a directory, Bye!"
		exit 1
	fi

	if [ "$1" = "import_db" ]; then
		if [ $# -lt 4 ]; then
			echo "expect at least 3 arguments, Bye!"
			exit 1
		fi

		if [ ! -e "$4" ]; then
			echo "$4 does not exist, Bye!"
			exit 1
		fi

		if [ ! -r "$4" ]; then
			echo "$4 cannot be read, Bye!"
			exit 1
		fi

		SQL_FILE=$4
	fi

	JSON_CONF="$2"
	MYSQL_DATA="$(realpath "$3")"
}

parse_json_file()
{
	MYSQL_INSTALL_DB_USER="$(jq -r .mysql_install_db.user "${JSON_CONF}")"
	MYSQL_INSTALL_DB_LDATA="${MYSQL_DATA}"
	MYSQL_ROOT_PASSWORD="$(jq -r .root_password "${JSON_CONF}")"
	MYSQL_ROOT_PASSWORD_ESCAPED=$(__basic_single_escape "${MYSQL_ROOT_PASSWORD}")
	MYSQL_CREATE_USER_REQUESTS_LEN="$(jq -r '.users | length' "${JSON_CONF}")"
	MYSQL_CREATE_DB_REQUESTS_LEN="$(jq -r '.databases | length' "${JSON_CONF}")"
	MYSQL_ARGS="-u root --socket=${MYSQL_INSTALL_DB_LDATA}/socket"
	MYSQL_ARGS_PASSWORD="${MYSQL_ARGS} -p${MYSQL_ROOT_PASSWORD_ESCAPED}"
	
	if [ "${MYSQL_INSTALL_DB_USER}" == "null" ]; then
		echo ".mysql_install_db.user is not in ${JSON_CONF}"
		exit 1
	fi

	if [ "${MYSQL_INSTALL_DB_LDATA}" == "null" ]; then
		echo ".mysql_install_db.ldata is not in ${JSON_CONF}"
		exit 1
	fi

	if [ "${MYSQL_ROOT_PASSWORD}" == "null" ]; then
		echo ".root_password is not in ${JSON_CONF}"
		exit 1
	fi
}

run_mysqld()
{
	echo "run mysqld_safe in background..."
	mysqld_safe \
		--datadir="${MYSQL_INSTALL_DB_LDATA}" \
		--wsrep-data-home-dir="${MYSQL_INSTALL_DB_LDATA}" \
		--pid-file="${MYSQL_INSTALL_DB_LDATA}/pid" \
		--socket="${MYSQL_INSTALL_DB_LDATA}/socket" &

	sleep 1
}

mysql_setup_db()
{
	MYSQL_REQUESTS=""

	echo -n "install mysql database..."
	if mysql_install_db \
		--user="${MYSQL_INSTALL_DB_USER}" \
		--ldata="${MYSQL_INSTALL_DB_LDATA}" > /dev/null 2>&1; then
		echo OK
	else
		echo "NOK: fail to install the mysql database"
		exit 2
	fi

	chown -R "${MYSQL_INSTALL_DB_USER}:${MYSQL_INSTALL_DB_USER}" "${MYSQL_INSTALL_DB_LDATA}"

	run_mysqld

	for i in $(seq 0 "$((MYSQL_CREATE_USER_REQUESTS_LEN-1))"); do
		MYSQL_REQUEST_USER="$(jq -r .users["${i}"].user "${JSON_CONF}")"
		MYSQL_REQUEST_HOST="$(jq -r .users["${i}"].host "${JSON_CONF}")"
		MYSQL_REQUEST_PASSWORD="$(jq -r .users["${i}"].password "${JSON_CONF}")"
		MYSQL_REQUEST_DATABASE="$(jq -r .users["${i}"].database "${JSON_CONF}")"
		MYSQL_REQUEST_TABLE="$(jq -r .users["${i}"].table "${JSON_CONF}")"
		MYSQL_REQUEST_PRIVILEGES="$(jq -r .users["${i}"].privileges "${JSON_CONF}")"

		if [ "${MYSQL_REQUEST_USER}" == "null" ]; then
			continue
		fi

		if [ "${MYSQL_REQUEST_HOST}" == "null" ]; then
			continue
		fi

		if [ "${MYSQL_REQUEST_PASSWORD}" == "null" ]; then
			continue
		fi

		if [ "${MYSQL_REQUEST_DATABASE}" == "null" ]; then
			MYSQL_REQUEST_DATABASE="*"
		fi

		if [ "${MYSQL_REQUEST_TABLE}" == "null" ]; then
			MYSQL_REQUEST_TABLE="*"
		fi

		if [ "${MYSQL_REQUEST_PRIVILEGES}" == "null" ]; then
			MYSQL_REQUEST_PRIVILEGES="ALL PRIVILEGES"
		fi

		MYSQL_REQUEST_USER_HOST="'${MYSQL_REQUEST_USER}'@'${MYSQL_REQUEST_HOST}'"
		MYSQL_REQUEST_DATABASE_TABLE="${MYSQL_REQUEST_DATABASE}.${MYSQL_REQUEST_TABLE}"

		MYSQL_CREATE_USER="CREATE USER ${MYSQL_REQUEST_USER_HOST} IDENTIFIED BY '${MYSQL_REQUEST_PASSWORD}';"
		MYSQL_GRANT_PRIVILEGES="GRANT ${MYSQL_REQUEST_PRIVILEGES} ON ${MYSQL_REQUEST_DATABASE_TABLE} TO ${MYSQL_REQUEST_USER_HOST} WITH GRANT OPTION;"

		MYSQL_REQUESTS="${MYSQL_REQUESTS}\\n${MYSQL_CREATE_USER}\\n${MYSQL_GRANT_PRIVILEGES}"
	done

	for i in $(seq 0 "$((MYSQL_CREATE_DB_REQUESTS_LEN-1))"); do
		MYSQL_REQUEST_DB_NAME="$(jq -r .databases["${i}"].name "${JSON_CONF}")"

		if [ "${MYSQL_REQUEST_DB_NAME}" == "null" ]; then
			continue
		fi

		MYSQL_CREATE_DB="CREATE DATABASE ${MYSQL_REQUEST_DB_NAME};"

		MYSQL_REQUESTS="${MYSQL_REQUESTS}\\n${MYSQL_CREATE_DB}\\n"
	done

	echo "Configure and secure the mysql database..."
	# shellcheck disable=SC2086
	mysql ${MYSQL_ARGS} <<EOF
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
${MYSQL_REQUESTS}
UPDATE mysql.user SET Password=PASSWORD('${MYSQL_ROOT_PASSWORD_ESCAPED}') WHERE User='root';
FLUSH PRIVILEGES;
EOF

	# shellcheck disable=SC2181
	if [ "${?}" -eq 0 ]; then
		echo OK
	else
		echo "NOK: failed to configure the mysql database"
		exit 3
	fi
}

mysql_shell()
{
	run_mysqld

	# shellcheck disable=SC2086
	mysql ${MYSQL_ARGS_PASSWORD}
}

mysql_import_db()
{
	run_mysqld

	# shellcheck disable=SC2086
	mysql ${MYSQL_ARGS_PASSWORD} < "${SQL_FILE}"
}

main()
{
	for program in $REQUIRED_PROGRAMS; do
		if ! command -v "$program" > /dev/null; then
			echo "$program is not installed, Bye!"
			exit 1
		fi
	done

	parse_args "$@"
	parse_json_file "${JSON_CONF}"

	case "$1" in
		setup_db)
			mysql_setup_db
			;;
		sh)
			mysql_shell
			;;
		import_db)
			mysql_import_db "${SQL_FILE}"
			;;
		*)
			echo "expect install_db|sh|import_db"
			exit 1
	esac
}

main "$@"
