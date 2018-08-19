mysql_install_db
================

`mysql_install_db` script initializes a folder to be ready to be used with
`mysql`.

This script depends on: jq, mysql mysqld_safe, mysql_install_db, and mysql_secure_installation.

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
	]
}
```

Then, pass this JSON file as well as the path to the mysql data folder as follow:
```
./mysql_install_db.sh example.json mysql_db/
```
