#!/usr/bin/env bash

REQUIRED_PROGRAMS="jq mysql mysqld_safe mysql_install_db mysql_secure_installation"

mysql_install_database()
{
	local FILE="$1"
	local MYSQL_DATA="$2"
	MYSQL_INSTALL_DB_USER="$(jq -r .mysql_install_db.user "${FILE}")"
	MYSQL_INSTALL_DB_LDATA="${MYSQL_DATA}"
	MYSQL_ROOT_PASSWORD="$(jq -r .root_password "${FILE}")"
	MYSQL_REQUESTS_LEN="$(jq -r '.users | length' "${FILE}")"
	MYSQL_REQUESTS=""

	if [ "${MYSQL_INSTALL_DB_USER}" == "null" ]; then
		echo ".mysql_install_db.user is not in ${FILE}"
		exit 1
	fi

	if [ "${MYSQL_INSTALL_DB_LDATA}" == "null" ]; then
		echo ".mysql_install_db.ldata is not in ${FILE}"
		exit 1
	fi

	if [ "${MYSQL_ROOT_PASSWORD}" == "null" ]; then
		echo ".root_password is not in ${FILE}"
		exit 1
	fi

	mysql_install_db \
		--user="${MYSQL_INSTALL_DB_USER}" \
		--ldata="${MYSQL_INSTALL_DB_LDATA}"

	mysqld_safe --datadir "${MYSQL_INSTALL_DB_LDATA}" &

	mysql_secure_installation << EOF
Y
${MYSQL_ROOT_PASSWORD}
${MYSQL_ROOT_PASSWORD}
Y
Y
Y
EOF

	for i in $(seq 0 "$((MYSQL_REQUESTS_LEN-1))"); do
		MYSQL_REQUEST_USER="$(jq -r .users["${i}"].user "${FILE}")"
		MYSQL_REQUEST_HOST="$(jq -r .users["${i}"].host "${FILE}")"
		MYSQL_REQUEST_PASSWORD="$(jq -r .users["${i}"].password "${FILE}")"
		MYSQL_REQUEST_DATABASE="$(jq -r .users["${i}"].database "${FILE}")"
		MYSQL_REQUEST_TABLE="$(jq -r .users["${i}"].table "${FILE}")"
		MYSQL_REQUEST_PRIVILEGES="$(jq -r .users["${i}"].privileges "${FILE}")"

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

		MYSQL_CREATE_USER="CREATE USER ${MYSQL_REQUEST_USER_HOST} IDENTIFIED BY '${MYSQL_REQUEST_PASSWORD}'"
		MYSQL_GRANT_PRIVILEGES="GRANT ${MYSQL_REQUEST_PRIVILEGES} ON ${MYSQL_REQUEST_DATABASE_TABLE} TO ${MYSQL_REQUEST_USER_HOST} WITH GRANT OPTION;"

		MYSQL_REQUESTS="${MYSQL_REQUESTS}\\n${MYSQL_CREATE_USER}\\n${MYSQL_GRANT_PRIVILEGES}"
	done

	mysql -u root -p << EOF
${MYSQL_ROOT_PASSWORD}
$(echo -e ${MYSQL_REQUESTS})
FLUSH PRIVILEGES;
EOF
}

main()
{
	for program in $REQUIRED_PROGRAMS; do
		if ! command -v "$program" > /dev/null; then
			echo "$program is not installed, Bye!"
			exit 1
		fi
	done

	if [ $# -ne 2 ]; then
		echo "expect exactly two arguments, Bye!"
		exit 1
	fi

	if [ ! -e "$1" ]; then
		echo "$1 does not exist, Bye!"
		exit 1
	fi

	if [ ! -r "$1" ]; then
		echo "$1 cannot be read, Bye!"
		exit 1
	fi

	if [ ! -e "$2" ]; then
		echo "$2 does not exist, Bye!"
		exit 1
	fi

	if [ ! -d "$2" ]; then
		echo "$2 is not a directory, Bye!"
		exit 1
	fi

	local FILE="$1"
	local MYSQL_DATA

	MYSQL_DATA="$(realpath "$2")"

	mysql_install_database "${FILE}" "${MYSQL_DATA}"
}

main "$@"
