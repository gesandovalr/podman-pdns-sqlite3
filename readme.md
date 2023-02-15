## Quick and Painless PDNS/PDNSADMIN/Recursor

### Description

* Podman container with NGINX/PDNS/PDNS-Recursor/PowerDNS-Admin/SQLITE3
* OS Base - Image, Almalinux:latest.
* DO NOT USE IT IT PRODUCTION THIS IS FOR TESTING ONLY. (I will not be held responsible for any damages or costs which might occur as a result of my advice or designs)

### Variables (ARGS)

* pdns_local_address: "0.0.0.0:5300"
* pdns_local_port: "5300"
* pdns_api_key: "mysupersecretkey"
* pdns_default_soa_name: "ns1.whatever.local"

### TODO

* Use Mariadb.
* Separate the containers.