# upgrade-mariadb-on-CWP-to-version-10.11-lts
This script automates the process of upgrading MariaDB on a CWP server.

How to upgrade mariadb on CWP to version 10.11 lts

Upgrading your database is essential for your application to run well. In this guide we provide 2 Methods you can use to upgrade.

Method 1: Automatic – Using the convenience script
This method will perform all the actions ensuring all checks and upgrades are done well.

Copy the Installation script below and run it.

bash <(curl -s https://gitlab.com/dannydev77/cwpdb-upgrade/-/raw/main/cwpdb-upgrade.sh || wget -qO- https://gitlab.com/dannydev77/cwpdb-upgrade/-/raw/main/cwpdb-upgrade.sh)

Running the Script.


Upgrade script complete.


Confirm status after Upgrade.


Method 2: Manual – Follow the steps below.
In this part, upgrade is being done from version 10.4 to 10.6

Adjust to meet your desired version.

Step 1: Perform backups
Use the command below to perform a backup of all databases

mysql -N -e 'show databases' | while read dbname; do mysqldump --complete-insert --routines --triggers --single-transaction "$dbname" > /home/backups/databases/"$dbname".sql; done

Step 2: Get the current db root password. Store it as it will be needed at later stages.
grep -i pass /root/.my.cnf

Step 3 : Verify the installed version and upgrade.
rpm -qa|grep -i maria|grep "-10.4."

First you need to change the MariaDB repo and replace it with MariaDB 10.6 repo:
sed -i 's/10.4/10.6/g' /etc/yum.repos.d/mariadb.repo

Second remove MariaDB 10.4 :
systemctl stop mariadb mysql mysqld
systemctl disable mariadb
rpm --nodeps -ev MariaDB-server

Third Install MariaDB 10.6 :
yum clean all
yum -y update "MariaDB-*"
yum -y install MariaDB-server
systemctl enable mariadb
systemctl start mariadb

Fourth you need to upgrade your database tables to the latest version:
After upgrade, you can use “mysql” command to verify the MariaDB version running on your server

mysql_upgrade –force

mysql –version

Lastly confirm with

systemctl status mariadb

====================================================
