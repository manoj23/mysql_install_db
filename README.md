mysql_install_db
================

`mysql_install_db.sh` script initializes a folder to be ready to be used with
`mysql`.
It allows to configure the root password as well as adding new users.

This script depends on: jq, mysql, mysqld_safe and mysql_install_db.

This script requires a JSON configuration file as follow:
```
{
	"mysql_install_db": {
		"user": "mysql"
	},
	"root_password": "1234",
	"users": [
		{
			"user": "mediawiki",
			"password": "1234",
			"host": "localhost",
			"privileges": "ALL PRIVILEGES",
			"database": "wiki",
			"table": "*"
		},
		{
			"user": "mediawiki",
			"password": "12345",
			"host": "savound.com",
			"database": "wiki"
		}
	],
	"databases": [ { "name": "wikidb" } ]
}
```

Then, pass this JSON file as well as the path to the mysql data folder as follow:
```
./mysql_install_db.sh install_db example.json /var/lib/mysql
```

To open the mysql terminal:
```
./mysql_install_db.sh sh example.json /var/lib/mysql
```
To execute an .sql file:
```
./mysql_install_db.sh import_db example.json /var/lib/mysql /foo.sql
```
