# fluent-plugin-pg-logical

## Overview

Fluentd input plugin to track of changes (insert/update/delete) event on PostgreSQL using logical decoding.

This plugin works as a WAL receiver of PostgreSQL and requires installation of logical decoding plugin to upstream PostgreSQL server.

## Installation

install with gem or fluent-gem command as:

`````
# for system installed fluentd
$ gem install fluent-plugin-pg-logical
`````

## Configuration

|Parameter|Type|Default|Remarks|
|:--------|:---|:------|:----------|
|host|string|'localhost'|-|
|port|integer|5432|-|
|user|string|'postgres'|-|
|password|string|nil|-|
|dbname|string|'postgres'|-|
|slotanme|string|nil|Required|
|plugin|string|nil|Required if 'create_slot' is specified|
|status_interval|integer|10|Specifies the minimum frequency to send information about replication progress to upstream server|
|tag|string|nil|-|
|create_slot|bool|false|Specify to create the specified replication slot before start|
|if_not_exists|bool|false|Do not error if slot already exists when creating a slot|

## Restriction
* Because logical decoding support only data changes (i.g. INSERT/UPDATE/DELETE), other changes such as DDL, sequence doesn't appear on fluentd input
* Replication slots are reuiqred as much as you connect with fluent-plugin-pg-logical

## Example with wal2json
fluent-plugin-pg-logical requires a logical decoding plugin to get logical change set.This is a example of use of fluent-plugin-pg-logical with [wal2json](https://github.com/eulerto/wal2json), which decodes WAL to json object.

1. Install wal2json to PostgreSQL
Please refer to "Build and Install" section in wal2json documentation.

2. Setting Configuration Parameters
```
<source>
  @type pg_logical
  host pgserver
  port 5432
  user postgres
  dbname replication_db
  slotname wal2json_slot
  plugin wal2json
  create_slot true
  if_not_exists true
</source>
```

3. Run fluentd
Launch fluentd.

4. Issue some SQL
```sql
=# CREATE TABLE hoge (c int primary key);
CREATE TABLE
=#INSERT INTO hoge VALUES (1), (2), (3);
INSERT 0 3
=# BEGIN;
BEGIN
=# UPDATE hoge SET c = c + 10 WHERE c = 1;
UPDATE 1
=# UPDATE hoge SET c = c + 20 WHERE c = 2;
UPDATE 1
=# COMMIT;
COMMIT
```

You will get,

```
2018-02-03 16:02:20.073058428 +0900 : "{\"change\":[]}"
2018-02-03 16:02:38.266394490 +0900 : "{\"change\":[{\"kind\":\"insert\",\"schema\":\"public\",\"table\":\"hoge\",\"columnnames\":[\"c\"],\"columntypes\":[\"integer\"],\"columnvalues\":[1]},{\"kind\":\"insert\",\"schema\":\"public\",\"table\":\"hoge\",\"columnnames\":[\"c\"],\"columntypes\":[\"integer\"],\"columnvalues\":[2]},{\"kind\":\"insert\",\"schema\":\"public\",\"table\":\"hoge\",\"columnnames\":[\"c\"],\"columntypes\":[\"integer\"],\"columnvalues\":[3]}]}"
2018-02-03 16:03:05.890485185 +0900 : "{\"change\":[{\"kind\":\"update\",\"schema\":\"public\",\"table\":\"hoge\",\"columnnames\":[\"c\"],\"columntypes\":[\"integer\"],\"columnvalues\":[11],\"oldkeys\":{\"keynames\":[\"c\"],\"keytypes\":[\"integer\"],\"keyvalues\":[1]}},{\"kind\":\"update\",\"schema\":\"public\",\"table\":\"hoge\",\"columnnames\":[\"c\"],\"columntypes\":[\"integer\"],\"columnvalues\":[22],\"oldkeys\":{\"keynames\":[\"c\"],\"keytypes\":[\"integer\"],\"keyvalues\":[2]}}]}"
```
Because current (at least up to version 10) PostgreSQL doesn't support DDL replication, `CREATE TABLE` command doesn't appear to fluentd input.


You can also monitor the activity of fluent-plugin-pg-logical on upstream server.

```sql
=# SELECT usename, application_name, sent_location, write_location, flush_location FROM pg_stat_replication ;

 usename  | application_name | sent_location | write_location | flush_location 
----------+------------------+---------------+----------------+----------------
 masahiko | pg-logical       | 0/15ADD70     | 0/15ADAC8      | 0/15ADAC8
(1 row)

```

## TODO
* Add travis test
* Table filtering

## Copyright

Copyright © 2018- Masahiko Sawada

## License

Apache License, Version 2.0
