#!/bin/bash

#This work is licensed under a Creative Commons Attribution 4.0 International License see http://creativecommons.org/licenses/by/4.0/

#version 0.1 initial release.
#version 0.2 - upgrade option added to simplify upgrading between OpenVPMS Versions.
#version 0.3 - new option enablessl will configure TLS certificates for tomcat.
#version 0.4 - enable locale settings.
#version 0.5 - changed to a menu driven newinstall using dialog. 
#version 0.6 - bugfixes related to openjdk versions, and removed Ubuntu Trusty from installer.
#version 0.7 - Default install version is now OpenVPMS 2.
#version 0.8 - Updated for Debian Stretch.
#version 0.9.1 - Now targeting Ubuntu LTS as this includes mysql-server and correct tomcat server version (while Debian does not).

#wishlist: more error checking and use of until loop for each function.
#todo: ensure no empty variables prior to running installer.
#todo: check required software is present before configuring mysql.
#todo: check vars are set in hibernate.properties prior to running dbtool.
#todo: split installmysql and configuredatabase functions.
#todo: define which situations require resetrootpass (it not for db upgrades).
#todo: catch empty variables (eg dbuser) prior to upgrading.
    #  eg,  
    #      if [ -z ${webapptmpdir+x} ]; then echo "var is unset!";exit 1; else echo "var is set to '$var'"; fi
#wishlist: suppress new mysql SSL connection warnings.
#wishlist: xdialog!
#wishlist: addclinic should handle a clinicname argument $2 
#wishlist: daily backups for a newinstall.
#wishlist: use zram to overcommit RAM safely.
#wishlist: download specific jdk, tomcat and mysql versions into /opt so that any distribution can use the script. 
#todo: allow tomcat write permissions to plugins locally so they can be used without manual intervention.
#todo: backup and restore functionality. 
#wishlist: package pinning to block mariadb in Stretch/Buster. 

#OpenVPMS compatibility notes:
#version 2.1.2 requires:
    # -openjdk 8 (in Stretch), or trial nvidia-openjdk-8-jre, or AdoptOpenJDK in buster.
    # -Tomcat version 8 (in Stretch along with version 11). 
    # -Mysql 5.5 (no longer available from debian official channel, was in Jessie) 
    #   -or 5.7 (officially available version, only works with ONLY_FULL_GROUP_BY removed).
    #	-todo: test mariadb 10.3 (in Buster) and it's mariadb-connector, or 10.1 (in Stretch - errors) with 2.1.1.
    # -mysql-connector-java must be 5.1.x, not the current version 8.
#version 1.9 and 2.0 require openjdk 8, Mysql 5.5(in Jessie) and Tomcat version 7 (all in debian Jessie).

varfile=/etc/openvpms-login-details.txt
if [ -f $varfile ]
then
	clear
	read -p "I noticed you have a $varfile file already. Would you like me to use those values (Y/n)?" yn
        case $yn in
	[Nn]* )
	;;	
	[Yy]*|*)
	. $varfile
	echo clinicname is set to $clinicname.
	#echo Press Enter to continue;read input
	chown root $varfile
	chmod 700 $varfile
	;;

	esac
fi

############## start define functions ###################
setclinicname () {
if [ -z ${clinicname+x} ] ; then
    export msg1="Please enter your clinic name. 
    This should be a short format of fewer than 12 characters with no spaces. It may contain letters and underscore.
    This short name is used to identify the mysql database and webapp. ->"
      DIALOG=${DIALOG-dialog}
    tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
    trap "rm -f $tempfile" 0 1 2 5 15
    $DIALOG \
	--backtitle "OpenVPMS Installer" \
	--clear --ok-label "Next" \
	--inputbox "`echo $msg1`" 16 51 2> $tempfile
    case $? in
      1)
	echo "Cancel pressed.";     exit
      ;;
      255)
	echo "ESC pressed.";    exit
      ;;
    esac
    clinicname=`cat $tempfile`
    #echo $clinicname
	#else
	#	echo "clinicname is set to ${clinicname}." 
fi
setdependentvars
}

setdependentvars () {
#note: use parameter expansion if variables are to be overridden by existing vars, eg in file.
papersize=${papersize-A4}
tcversion=${tcversion-8}
CATALINA_HOME=/usr/share/tomcat$tcversion    	;mkdir -p $CATALINA_HOME
CATALINA_BASE=/var/lib/tomcat$tcversion    	;mkdir -p $CATALINA_BASE 
jdkversion=${jdkversion-8}
tchost=${tchost-`hostname -s`}
ssltchost=${ssltchost-thevillagevet.co}
vpmsinstallversion=${vpmsinstallversion-2.1.2}  
jarversion="5.1.48"   #mysql-connector version. Caution with version 8 or newer.
dbname=${dbname-"$clinicname"}
dbuser=${dbuser-"$clinicname"}
dbuserpass=${dbuserpass-`< /dev/urandom tr -dc A-Z-a-z-0-9 | head -c15;echo;`}
rootdbpass=${rootdbpass-$dbuserpass}
tcusername=${tcusername-$dbuser}
tcpass=${tcpass-$dbuserpass}
dbhost=${dbhost-localhost}
webappuser=${webappuser-$dbuser}
mysqlversion=${mysqlversion-5.5}
vpmsinstallerdir=${vpmsinstallerdir-/opt/openvpms-release-"$vpmsinstallversion"}	;mkdir -p $vpmsinstallerdir
webapptmpdir="/opt/webapptmpdir-$vpmsinstallversion"	;mkdir -p $webapptmpdir
webappinstalldir="$CATALINA_BASE/webapps/$clinicname" 	;mkdir -p $webappinstalldir
openvpmsapppass="$tcpass"
reportsdir="$vpmsinstallerdir/reports/"
clinictheme=${clinictheme-"green"}
my_cnf=/etc/mysql/my.cnf
DEBIAN_FRONTEND=dialog
}

startscreen () {
setdependentvars
gimme dialog
DIALOG=${DIALOG-dialog}
tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
trap "rm -f $tempfile" 0 1 2 5 15
$DIALOG \
    --backtitle "OpenVPMS Installer" \
    --title "Installer Options" \
    --clear  --ok-label "Next" \
    --cancel-label "Exit" \
    --menu "Please select:" 0 0 4 \
    "1" "New Installation (choose this for first timers)." \
    "2" "Upgrade an existing Installation to ${vpmsinstallversion}." \
    "3" "Add an additional clinic to this Server." \
    "4" "Install Chinese Fonts." \
    "5" "Install a specific version." \
    "6" "test JDBC." \
    "7" "Upgrade to a specific version."  2> $tempfile
retval=$?
choice=`cat $tempfile`
case $retval in
  0)
    echo "'$choice' was selected" ;sleep 1
  ;;
  1)
    echo "Cancel pressed."
    exit
  ;;
  255)
    echo "ESC pressed."
    exit
  ;;
esac
  
case $choice in
    4)
    export selection=cnfont
    
    ;;
    11)
    export selection=enablessl
    
    ;;
    1)
    export selection=newinstall
    ;;
    2)
    export selection=upgrade
    clear
    echo You have selected to upgrade your installation to $vpmsinstallversion.;sleep 1
    ;;
    7)
    export selection=upgrade
    clear;echo Please enter a version number to upgrade to:;read vpmsinstallversion;sleep 1
    export vpmsinstallversion=$vpmsinstallversion
    ;;
    [w]|webappinstall)
    export selection=webappinstall
    
    ;;
    6)
    export selection=jdbctest
    #export tcversion=8
    clinicname=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c4;echo;`
    ;;
    3)
    export selection=addclinic
    
    ;;
    5)
    customversion
    export selection=newinstall
;;
esac
#echo Debug;echo your exit status is $? ; sleep 10
#act on selection
chmod +x $0 
#$0 $selection
bash $0 $selection
#todo: add autoinstall option which accepts arguments $0 auto clinicname and could either install a new system, or add clinicname to existing. Must be non-interactive and either set mysql password or source it from file.
}
customversion () {
export msg1="Please note that you should not install differing versions on the same server, as this will cause instability. \n
Please enter the specific version number you wish to install. For example, you might enter 2.0.2"
DIALOG=${DIALOG-dialog}
    tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
    trap "rm -f $tempfile" 0 1 2 5 15
    $DIALOG \
	--backtitle "OpenVPMS Installer" \
	--title "Enter a specific version to install" \
	--clear \
	--inputbox "`echo $msg1`" 0 0 2> $tempfile
    case $? in
      1)
	echo "Cancel pressed.";     exit
      ;;
      255)
	echo "ESC pressed.";    exit
      ;;
    esac
    vpmsinstallversion=`cat $tempfile`
}

SSLPREP () {
    #todo: automatically configure certbot based on above tchost name and by grepping for DocumentRoot in apache2. Certbot needs $ grep jessie-backports /etc/apt/sources.list || echo "deb http://deb.debian.org/debian `lsb_release -sc`-backports main contrib non-free" >> /etc/apt/sources.list && apt-get update -q
    case `lsb_release -sc` in
    trusty)
    gimme wget
    installdir=/opt/certbot-auto
    mkdir -p $installdir
    cd $installdir && wget https://dl.eff.org/certbot-auto
    chmod a+x certbot-auto
    export certbotstandalone=$installdir/certbot-auto 
    export certbotrenew=$installdir/certbot-auto renew
    CreateTLSCert
    echo End of SSL configuration. Press Enter to continue.
    read input
    ;;
    jessie)
    #use certbot-auto; the jessie-backports package is unstable.
    gimme wget
    installdir=/opt/certbot-auto
    mkdir -p $installdir
    cd $installdir && wget https://dl.eff.org/certbot-auto
    chmod a+x certbot-auto
    export certbotstandalone=$installdir/certbot-auto 
    export certbotrenew=$installdir/certbot-auto renew
    CreateTLSCert
    ;;
    *) 
    echo "I do not yet support your installed linux distribution".
    echo "However, I can use certbot-auto. Press Enter to try this, or Ctrl+C to exit."
    read input
    installdir=/opt/certbot-auto
    mkdir -p $installdir
    cd $installdir && wget https://dl.eff.org/certbot-auto
    chmod a+x certbot-auto
    export certbotstandalone=$installdir/certbot-auto
    export certbotrenew=$installdir/certbot-auto renew
    CreateTLSCert
    esac
}

CreateTLSCert () {
    clear
    echo I need to know your domain name. Please supply the full domain, eg. www.thevillagevet.co
    read tlshostname
    echo checking with ping.
    ping -c 1 $tlshostname || echo I could not ping your host, you should NOT continue. && echo I can ping your host.
    echo 
    #echo Thankyou. I must now stop your webserver temporarily to retrieve the certificates using certbot. Press Enter to continue or Ctrl+C to exit.
    #read input
    service apache2 stop
    $certbotstandalone -d $tlshostname 
    echo Press Enter to continue
    read input
    grep -q certbot /var/spool/cron/crontabs/root >/dev/null || echo "3 5 * * *  $certbotrenew >/dev/null 2>&1" >> /var/spool/cron/crontabs/root
    service apache2 start
    #configure the tckeys script to convert keys to keystore
    echo Installing a script to convert the retrieved certificate into a Tomcat keystore file
    mkdir -p /usr/local/sbin/
    script=/usr/local/sbin/tckeys.sh
    password1=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c15;echo;`
cat << 'EOF' > /usr/local/sbin/tckeys.sh
#!/bin/sh
#v0.15 - cleanup old keys.
#v0.14 - bugfixes for broken SSL chain error at PV.
#v0.13 - bugfixes
#v0.12 - check if key exists when running createtlscerts
#v0.11 - can update server.xml

    if [ -s $SHAREDCONFIGS/$z ] ; then
       . $SHAREDCONFIGS/$z  
    fi

case `hostname -s` in
pulsevet|production1)
    export tlsnames="fourpaws.hk pulsevet.co thevillagevet.co"
;;
pulsevet-db2)
 export tlsnames=openvpms.pulsevet.co
;;
loungetv)
    export tlsnames=loungetv.damiensolley.com
;;
cvv-db1)
    export tlsnames=openvpms.thevillagevet.co
;;
fourpaws-dbserver)
    export tlsnames=openvpms.fourpaws.hk
;;
*)
    export tlsnames=`hostname --fqdn`
;;
esac

if [ -f $KEYS/`hostname -s`.tckey ] ; then
 . $KEYS/`hostname -s`.tckey
fi

if [ -s /opt/puppets/shared-configs/puppetstaticvariables.sh ] ; then
  . /opt/puppets/shared-configs/puppetstaticvariables.sh 
fi


KEYS=${KEYS-"/opt/puppets-keys/"}
lsdir=$KEYS/letsencrypt/
mkdir -p $lsdir
keyalias=tomcat
mypass=${mypass-"easypassword"}
pkcs12_cert=$lsdir/tmp_cert.p12
tcPFXkey=/etc/ssl/private/tomcat_cert.pfx

#is this still used?
tckeystore=/etc/ssl/private/tomcat_keystore.jks

#remove tckeystore to prevent wrong password error with autogenerated passwords:
rm -f $tckeystore  > /dev/null 2>&1

createtlscerts () {
for i in $tlsnames ; do 
privatekeyfile=$lsdir/live/${i}/privkey.pem
certfile=$lsdir/live/${i}/cert.pem
chainfile=$lsdir/live/${i}/chain.pem
    if [ -f $certfile ] ; then
     certbot renew   -n  > /dev/null
    else
     gimme certbot
     echo Using Certbot in standalone mode to generate your TLS key.
     certbot certonly --standalone -d $i --preferred-challenges http  || sleep 5 
    fi
done

}

createtccerts () {
for i in $tlsnames ; do 
privatekeyfile=$lsdir/live/${i}/privkey.pem
certfile=$lsdir/live/${i}/cert.pem
chainfile=$lsdir/live/${i}/chain.pem
#creating bundle for tomcat to use: 
#use https://www.sslshopper.com/ssl-checker.html#hostname=pulsevet.co:8444 to check. 
#guide from: https://community.letsencrypt.org/t/using-lets-encrypt-with-tomcat/41082/6
echo Converting your key for use with tomcat.
openssl pkcs12 -export -out $tcPFXkey -inkey $privatekeyfile -in $certfile  -certfile $chainfile -password pass:$mypass
chmod 750 $tcPFXkey
chgrp ssl-cert $tcPFXkey
done
}

createtccerts_old () {
#this old method resulted in broken chain error in some browsers: 
if [ -f $privatekeyfile ] ; then
    #openssl creates and converts the keys to pkcs12 format:
    openssl pkcs12 -export -in $certfile  -inkey $privatekeyfile -out $pkcs12_cert -name tomcat -CAfile $chainfile -caname root -password pass:$mypass # > /dev/null
    openssl pkcs12 -in $pkcs12_cert -passin pass:$mypass \
     -passout pass:$mypass \
     | egrep -i 'friendlyName:|subject=|key attributes'
    #delete any old key in keystore: probably obsolete, as we start with a blank keystore.
    #keytool -delete  -keystore $tckeystore -storepass $mypass  -alias $keyalias  #>/dev/null 2>&1
    #import the pkcs12 key to keystore:
    keytool -importkeystore -noprompt -deststorepass $mypass \
     -destkeystore $tckeystore -srckeystore $pkcs12_cert \
     -srcstoretype PKCS12 -srcstorepass $mypass  # > /dev/null
    #add the cert created to keystore: 
    keytool -list -v -keystore $tckeystore -storepass $mypass \
     | egrep -i 'alias name|chain length|certificate\[|owner:'
fi
}
setupcron () {
    grep -q $SHAREDCONFIGS/`basename ${0}`  /var/spool/cron/crontabs/root || echo "3 3 * * *   nice $SHAREDCONFIGS/`basename ${0}` > /dev/null 2>&1 ">>  /var/spool/cron/crontabs/root
}

updatetcserverxml () {
echo Updating Tomcat configuration to use the new key.
tcf=`ls /etc/tomcat*/server.xml `
for i in $tcf ; do 
  if [ -f $i ] ; then 
    sed -i "/keystoreFile=/c\keystoreFile=\'$tcPFXkey'\ keystoreType='PKCS12'\ keystorePass=\'$mypass\'"  $i
  fi
done
}


#main:
setupcron
createtlscerts 
createtccerts
updatetcserverxml 

EOF
    echo certificate renewal script installed to $script
    grep $script /var/spool/cron/crontabs/root >/dev/null || echo "5 4 * * *  $script >/dev/null 2>&1 " >> /var/spool/cron/crontabs/root
    #install keystore to server.xml
    configuretomcatserver
    #ensure passwords are in sync between server.xml and keystore file
    sed -i "s/REPLACEMEWITHSEDPASSWD/$password1/g" /etc/tomcat$tcversion/server.xml
    sed -i "s/REPLACEMEWITHSEDPASSWD/$password1/g" $script
    sed -i "s/REPLACEMEWITHSEDTLSNAME/$tlshostname/g" $script
    #run the script:
    chmod 700 $script
    $script # || echo there was an error this script always outputs to stderr
    echo
    echo Tomcat must be restarted to read the keystore file. Press enter to restart it.
    read input
    service tomcat$tcversion restart
    #todo: telnet check on port 8443 ; if successful, then flag it and notify within important message.
}

checkmysqlrootpass () {
#todo: if database already exists and is accessible, no need to set rootdbpass.
#echo Checking user root connection to mysql using password $rootdbpass .
#official mysql uses no root passwrod: 
case `lsb_release -sc` in
jessie|stretch|buster|bionic)
until mysql -u root -e ";" ; do
	echo unable to connect to mysql as user root. Do you need to reset the password? ;sleep 1
	#before resetting, give the user a chance? Or best to automate this step?
	resetrootdbpass
	#echo "I can help you set a new root database password. Please press Enter to continue";read input
	#dpkg-reconfigure mysql-server-$mysqlversion #trial other non-interactive methods; consider apt-get remove and reinstall with debconf-set-selections
      #todo: two pieces of logic; first to check root connection (and correct as necessary) and a second to check connection to $dbname using $dbuser - correct if error.
      #todo: implement checkmysqldbuserconnection
       clear
done
echo mysql server configured.;sleep 1
;;
esac
}

mysqlconfiguration () {
case $selection in
#if newinstall is selected, these questions should be skipped...
newinstall|jdbctest)
    choice=0
;;
*)
    export msg1="I will install a known working MySQL database configuration. \n
     - Choose Yes to install the recommended MySQL configuration file. \n
     - Choose no you want to configure MySQL manually."
    DIALOG=${DIALOG-dialog}
    tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
    trap "rm -f $tempfile" 0 1 2 5 15
    $DIALOG --backtitle "OpenVPMS Installer" --clear \
	--title "Configuring Database" \
	--yesno "`echo $msg1`" 0 0  2> $tempfile
    choice=$?
;;
esac

case $choice in
  0)
  #OK, configure the db
  choice=Y
  ;;
  1)
    echo "Cancel pressed."
  ;;
  255)
    echo "ESC pressed."
  ;;
esac

case $choice in 
    [Yy]* ) 
    #echo Configuring Mysql to use UTF8 "(This overwrites the existing configuration with known good combinations of utf8 variables)"
    #note: use of utf8mb4 may cause column lengths to overrun, preventing migrate.sql from running. Stick with the tried and true: utf8
    #fair warning already given: echo Press Enter to configure mysql...;read response;clear
    mkdir -p /etc/mysql
    cp $my_cnf /etc/mysql/my.cnf.bak
cat << 'EOF' > $my_cnf
[client]
port            = 3306
socket          = /var/run/mysqld/mysqld.sock
#utf8 is important for HK and 1.9.1
default-character-set=utf8
[mysqld_safe]
socket          = /var/run/mysqld/mysqld.sock
nice            = 0

[mysqld]
user            = mysql
ssl=0
pid-file        = /var/run/mysqld/mysqld.pid
socket          = /var/run/mysqld/mysqld.sock
port            = 3306
basedir         = /usr
datadir         = /var/lib/mysql
tmpdir          = /tmp
lc-messages-dir = /usr/share/mysql
skip-external-locking
collation-server = utf8_unicode_ci
init-connect='SET NAMES utf8'
character-set-server = utf8
key_buffer_size         = 256M
sort_buffer_size = 2M
read_buffer_size = 2M
table_open_cache = 4096
read_rnd_buffer_size = 64M
myisam_sort_buffer_size = 64M
thread_cache_size = 8
#query_cache_size = 16M
max_allowed_packet      = 32M
thread_stack            = 192K
#see https://www.openvpms.org/documentation/csh/2.0/reference/tuning
#change this to use at most 80% of system memory, or 50% as a sensible default:
innodb_buffer_pool_size=2G
#incompatible with 5.7: innodb_additional_mem_pool_size=20M
innodb_flush_method=O_DIRECT
myisam-recover-options   = BACKUP
log_error = /var/log/mysql/error.log
#log_bin                        = /var/log/mysql/mysql-bin.log
#expire_logs_days       = 10
#max_binlog_size   = 100M
sql_mode = "STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"

[mysqldump]
quick
quote-names
default-character-set=utf8

[mysql]
ssl=0
default-character-set=utf8
#For OpenVPMS 2.1 with mysql 5.7, the sql_mode must be changed to remove ONLY_FULL_GROUP_BY. This is done by configuring the server options file, or via MySQL Workbench.
#borked: todo: http://drib.tech/programming/turn-off-sql-mode-only_full_group_by-mysql-5-7 sql_mode = "STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION"
#instead run this command: echo " SET GLOBAL sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));" | mysql -u root

[isamchk]
key_buffer              = 16M
includedir /etc/mysql/conf.d/

EOF
    #todo: logic check to ensure can connect to mysql port 3306 after this: 
	#if nc -z -v -w2 localhost 3306 ; then echo good;fi
    #todo: check mysqlversion is > 5.1 before applying this: 
    #
    if !  echo " SET GLOBAL sql_mode=(SELECT REPLACE(@@sql_mode,'ONLY_FULL_GROUP_BY',''));" | mysql -u root 
	then echo Unable to set sql_mode correctly. Resetting password for root.
	#exit
    fi
    #additional sanity check: 
    if echo "SELECT @@sql_mode;" | mysql -u root | grep -q ONLY_FULL_GROUP_BY; then
       echo sql_mode is not set correctly!
       exit
    fi
    service mysql restart
	    #until checkmysqlrootpass; do
	    #  echo Retrying mysql configuration
	    #done
    if [ ! -f /etc/mysql/conf.d/bind-address.conf ] 
	    then
	    echo "Modified by `basename $0` " > /etc/mysql/conf.d/bind-address.conf
	    echo bind-address=127.0.0.1 >> /etc/mysql/conf.d/bind-address.conf
    fi
    #echo if you want to allow mysql access from more hosts than localhost, Please comment out the bind-address line in in the following file: /etc/mysql/conf.d/bind-address.conf; echo
    #todo: telnet or nc check to ensure mysql up and port open
    ;;
    esac
}


preparevpmsinstaller () {
    DLURL=${DLURL-"http://repository.openvpms.org/releases/org/openvpms/openvpms-release/${vpmsinstallversion}/openvpms-release-${vpmsinstallversion}.zip "}
    cd /opt && wget -c ${DLURL} > /dev/null  
    cd /opt/ && unzip  -u /opt/openvpms-release-${vpmsinstallversion}.zip  > /dev/null
    #using sed with the third instance of admin works for now:
    #todo: fix for 2.1.1, or use default 'openvpms' user:
	    #disabled for testing: 
	    sed -i  "s/admin/$openvpmsapppass/3" $vpmsinstallerdir/import/data/base.xml
	    #disabled for testing: 
	    sed -i  "s/admin/$webappuser/1" $vpmsinstallerdir/import/data/base.xml
	    #and change the default 'vet' password:
	    sed -i  "s/vet/$openvpmsapppass/3" $vpmsinstallerdir/import/data/base.xml
    #point 1
    #configure permissions so plugins work: 
    chown -R tomcat$tcversion $vpmsinstallerdir
}

blockmariadb () {
echo "Package: libmariadb*
Pin: release *
Pin-Priority: -1

Package: mariadb*
Pin: release *
Pin-Priority: -1
" > /etc/apt/preferences.d/block_mariadb
}
checkvars () {
    echo at this point in the script, important variables are: 
    echo clinicname is $clinicname
    echo while clinicname with vpmsinstallversion is $clinicname$vpmsinstallversion
    echo papersize is $papersize
    echo tcversion is $tcversion
    echo tchost is $tchost
    echo vpmsinstallversion is $vpmsinstallversion
    echo dbuserpass is $dbuserpass
    echo dbuser is $dbuser
    echo dbname is $dbname
    echo rootdbpass is $rootdbpass
    echo tcusername is $tcusername
    echo tcpass is $tcpass
    echo dbhost is $dbhost
    echo mysqlversion is $mysqlversion
    echo vpmsinstallerdir is $vpmsinstallerdir with variable vpmsinstallversion $vpmsinstallversion 
    echo webapptmpdir is $webapptmpdir and tcversion $tcversion
    echo Press Enter to continue...;read response;clear
}

mkdir -p /opt/

installrequiredsoftware () {
    gimme lsb-release dialog
    case `lsb_release -sc` in
    Core)
	yum update
	#mariadb is at 5.5 in Core
	yum install mysql-connector-java.noarch mariadb wget
	export my_cnf=/etc/my.cnf
	mysqlconfiguration
   ;;
   buster)
    #echo "OpenVPMS requires java JDK 8, which is not available for Debian".
    jdkversion=8
    tcversion=9
    mysqlversion="5.7"  
    release=`lsb_release -sc`
    
    release=stretch installofficialmysql   #as of 2019-04-19 there is no mysql-server packages available for Buster.
    installofficialjdk-jre   # Works using www.azul.com openjdk packages.
    gimme bc  libreoffice-writer libreoffice-base libreoffice-java-common  wget unzip sed fonts-dejavu   
    #wishlist: get tomcat version that works with azul packages: gimme openjdk-$jdkversion-jre tomcat$tcversion-admin  tomcat$tcversion libtcnative-1
        #tcnative pulls in apr so plain PEM certificates can be used.
    adduser tomcat$tcversion ssl-cert > /dev/null 2>&1
#wishlist: automatically configure certbot based on above tchost name and by grepping for DocumentRoot in apache2. Certbot needs $ grep $release-backports /etc/apt/sources.list || echo "deb http://deb.debian.org/debian `lsb_release -sc`-backports main contrib non-free" >> /etc/apt/sources.list && apt-get update -q
    #missing directories after install: 
    for i in "
    /usr/share/tomcat$tcversion/common/classes
    /usr/share/tomcat$tcversion/server/classes
    /usr/share/tomcat$tcversion/shared/classes
    /var/lib/tomcat$tcversion/server/classes
    /var/lib/tomcat$tcversion/shared/classes
    /usr/share/tomcat$tcversion/shared/classes
    "
    do  mkdir -p $i;chown tomcat$tcversion $i -R
    done
   ;;
   stretch|bionic)
    jdkversion=8 
    tcversion=8
    mysqlversion="5.7"
    release=`lsb_release -sc`
    setdependentvars
    #echo 'deb http://deb.debian.org/debian-security stretch/updates main 
    #deb http://security.debian.org/ stretch/updates main contrib non-free
    #deb  http://deb.debian.org/debian stretch main contrib non-free
    #' > /etc/apt/sources.list.d/stretch.list ; apt update > /dev/null 2>&1
    #doesn't work due to perl dependencies: installdebianjessiemysql
    installofficialmysql
    apt-get install -y bc libreoffice-writer libreoffice-base libreoffice-java-common  wget unzip sed fonts-dejavu   openjdk-$jdkversion-jre tomcat$tcversion-admin  tomcat$tcversion libtcnative-1 
        #tcnative pulls in apr so plain PEM certificates can be used.
    adduser tomcat8 ssl-cert > /dev/null 2>&1
#wishlist: automatically configure certbot based on above tchost name and by grepping for DocumentRoot in apache2. Certbot needs $ grep $release-backports /etc/apt/sources.list || echo "deb http://deb.debian.org/debian `lsb_release -sc`-backports main contrib non-free" >> /etc/apt/sources.list && apt-get update -q
    #missing directories after install: 
    for i in "
    /usr/share/tomcat$tcversion/common/classes
    /usr/share/tomcat$tcversion/server/classes
    /usr/share/tomcat$tcversion/shared/classes
    /var/lib/tomcat$tcversion/server/classes
    /var/lib/tomcat$tcversion/shared/classes
    /usr/share/tomcat$tcversion/shared/classes
    "
    do  mkdir -p $i;chown tomcat$tcversion $i -R
    done
    ;;
   jessie)
       #note: do not use this file for jessie - use the archived copy.
       echo note: do not use this file for jessie - use the archived copy.;exit 
   ;;
    *)
    export msg1="I don't recognise your system. This installer is not likely to work!
OpenVPMS has very specific requirements for mysql version and tomcat compatibility. Press Yes to attempt installation, or No to exit:"
DIALOG=${DIALOG-dialog}
tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
trap "rm -f $tempfile" 0 1 2 5 15
$DIALOG \
    --backtitle "OpenVPMS Installer" \
    --title "Unsupported Linux Version" \
    --clear \
    --yesno "`echo $msg1`" 0 0  2> $tempfile
case $? in
  1)
    echo "Cancel pressed.";     exit
  ;;
  255)
    echo "ESC pressed.";    exit
  ;;
esac
entry1=`cat $tempfile`

    apt-get -q  -y install bc mysql-server tomcat8 tomcat8-admin libreoffice-writer libreoffice-base libreoffice-java-common libmysql-java  wget unzip sed fonts-dejavu || apt-get -q   install openssh-server mysql-server-$mysqlversion tomcat$tcversion tomcat$tcversion-admin libreoffice-writer libreoffice-base libreoffice-java-common libmysql-java  wget unzip sed fonts-dejavu
    chown tomcat$tcversion /usr/share/tomcat$tcversion -R
    ;;
    esac

#miscellaneous:
#configure php in apache2 (only for phpmyadmin): 
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 20M/g' /etc/php5/apache2/php.ini >/dev/null 2>&1
sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 20M/g' /etc/php7/apache2/php.ini >/dev/null 2>&1
#disablepropercasing () {
	for i in /var/lib/tomcat*/webapps/*/WEB-INF/classes/localisation/propercase.properties; do 
	  if (test `wc -l $i|awk '{print $1}'` -gt "1" ); then
	      echo "#Disabled by `basename $0` " > $i
	  fi
	done
#configure connector:
mkdir -p $vpmsinstallerdir/lib/ /usr/share/tomcat${tcversion}/lib/ 
ln -s -f /usr/share/java/mysql-connector-java-*.jar $vpmsinstallerdir/lib/  || exit 1
ln -s -f /usr/share/java/mysql-connector-java-*.jar /usr/share/tomcat${tcversion}/lib/  || echo an error occurred.

#configure varfile: 
echo "# Login at http://${tchost}:8080/${clinicname}/ with username $webappuser and password $openvpmsapppass" > $varfile 
echo clinicname=${clinicname} >> $varfile 
echo webappuser=$webappuser >> $varfile 
echo dbuser=$dbuser>> $varfile 
echo "#set dbuserpass to $openvpmsapppass" >> $varfile 
echo dbuserpass=$openvpmsapppass >> $varfile 
echo openvpmsapppass=$openvpmsapppass >> $varfile 
echo dbname=$dbname  >> $varfile 
#not needed for mysql 5.7.6 and newer: echo rootdbpass=$rootdbpass >> $varfile
chmod 600 $varfile 
}

laststeps () {
webappinstall 
configuretcusers
title=All\ Done
msg1="IMPORTANT PASSWORD: \n
login at http://${tchost}:8080/${clinicname}/ with username $webappuser and password $openvpmsapppass \n
I have saved these details in the file $varfile \n
It may take a minute for the web app to be automatically started.\n
Finally, don't forget to visit http://www.openvpms.org/documentation/csh/`echo $vpmsinstallversion |cut -c 1,2,3`/reference/setup to learn about customising your system."
DIALOG=${DIALOG-dialog}
$DIALOG --backtitle "OpenVPMS Installer" --clear --ok-label "Finish" \
    --title "$title" \
    --msgbox "`echo $msg1`" 0 0  

 #need to refresh base.xml between runs as now using $webappuser #need to refresh it between runs as now using $webappuser
 mv $vpmsinstallerdir/import/data/base.xml $vpmsinstallerdir/import/data/base.xml.$clinicname     
	#rm -fr $vpmsinstallerdir
	#rm -fr $webapptmpdir
rm -f $vpmsinstallerdir/import/data/base.xml  #need to refresh it between runs as now using $webappuser
}

asktocontinuemysql () {
    while true; do
    read -p "Do you wish to continue (y/n)?" yn
    case $yn in
    [Yy]* ) echo continuing; break;;
    [Nn]* ) exit;;
    *) echo "Please answer yes or no.";;
    esac
    done
}
dbmigrate () {
	case $vpmsinstallversion in
	2*)
		echo Upgrading version $vpmsinstallversion using dbtool.
		cd $vpmsinstallerdir/bin/;./dbtool --update  #update doesn't use CLI credentials: -u $dbuser -p $dbuserpass  #|| echo Major error!
		sleep 1
	;;
	#wishlist, handle upgrade over multiple version numbers (eg 1.8 to 2.0)
	1.*)
	    for i in `seq $strippedoldversion 0.1 $maxmigratescript`; do echo  migrating $i to `echo  "$i+.1"|bc`
	    mysql -u $dbuser -p$dbuserpass $dbname  < $vpmsinstallerdir/update/db/migrate-$i-to-`echo  "$i+.1"|bc`.sql  || exit
	    done
	;;
	esac
}

installofficialjdk-jre () {
#note: zulu doesn't distribute .deb files.
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 0xB1998361219BD9C9 && \
echo "deb http://repos.azulsystems.com/debian stable main" > /etc/apt/sources.list.d/zulu-openjdk.list
apt -q update
gimme zulu-$jdkversion
}

installofficialmysql () {
blockmariadb
#connector config:
case `lsb_release -sc` in 
bionic)
    gimme mysql-server-$mysqlversion
    gimme libmysql-java 
;;
stretch)
    #apt-get remove --purge libmysql-java  
     file1=mysql-apt-config_0.8.14-1_all.deb
     #todo: stop downloading duplicates:
     if [ ! -f $file1 ] ; then
	 wget -c http://repo.mysql.com/$file1
     fi
     export  DEBIAN_FRONTEND=noninteractive 
     dpkg -i $file1 #wishlist: make this noninteractive
     echo "deb http://repo.mysql.com/apt/debian/ $release mysql-$mysqlversion 
     deb http://repo.mysql.com/apt/debian/ $release mysql-apt-config
     deb http://repo.mysql.com/apt/debian/ $release mysql-tools" > /etc/apt/sources.list.d/mysql.list #|| Error installing MySQL signing key. && exit
     apt update -q
     gimme debconf-utils 
     for i in  bc mysql-community-server ; do 
     gimme $i
     done
     gimme libmysql-java
;;
esac
}

dlmysqlofficialconnector () {
     url="https://cdn.mysql.com//Downloads/Connector-J"
     cd /dev/shm && \
     wget -c $url/mysql-connector-java-$jarversion.tar.gz && \
     tar -zxf mysql-connector-java-$jarversion.tar.gz  && \
     mkdir  -p  /usr/share/tomcat${tcversion}/lib/  $vpmsinstallerdir/lib/ && \
     cp -f mysql-connector-java-$jarversion/mysql-connector-java-$jarversion-bin.jar  $vpmsinstallerdir/lib/ && \
     cp -f mysql-connector-java-$jarversion/mysql-connector-java-$jarversion-bin.jar   /usr/share/tomcat${tcversion}/lib/ && \  
     chmod 644  $vpmsinstallerdir/lib/mysql*   /usr/share/tomcat${tcversion}/lib/mysql*  && \ 
     echo Installed mysql-connector-java-$jarversion.jar || exit 1 

}

installmariadb () {
rm -f /etc/apt/preferences.d/block_mariadb && apt update
apt-get install libmysql-java -y

#fixed: mysql error with /usr/share/tomcat8/lib/mysql-connector-java-5.1.48-bin.jar -> error with mariadb "Could not resolve placeholder 'jdbc.driverClassName' in string value "${jdbc.driverClassName}"; nested exception"
#debug: testing with /mariadb-java-client-2.4.4.jar -> "Could not resolve placeholder 'jdbc.driverClassName' in string value "${jdbc.driverClassName}"; nested exception"
apt install mysql-server -qy  #testing with mariadb 10.1
}

runupgrade () {
	#todo: upgrade should check and fix collation, ie utf8_general_ci vs old utf8_unicode_ci
	#todo: alter table <some_table> convert to character set utf8 collate utf8_general_ci;
	#To set default collation for the whole database,
	#ALTER DATABASE  `databasename` DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci
	clear
	echo Upgrading a VPMS system.
	#echo "I will execute alter database $dbname DEFAULT character set utf8 COLLATE utf8_general_ci | mysql -u $dbuser -p$dbuserpass "
	#ensure collation is correct: 
	if ! `echo "alter database $dbname DEFAULT character set utf8 COLLATE utf8_general_ci " | mysql -u $dbuser -p$dbuserpass  ` ; then
	    echo  
	    echo "echo alter database $dbname DEFAULT character set utf8 COLLATE utf8_general_ci  | mysql -u $dbuser -p$dbuserpass " 
	    echo Unable to update collation. You can exit by pressing Ctrl-C or Enter to continue.
	    read input
	fi
	#phpmyadmin could also be used to update collation.
	#not necessary in first test: echo "SELECT table_name FROM information_schema.tables where table_schema=$dbname | mysql -u $dbuser -p $dbuserpass "
	#todo: retrieve installed version number and use $vpmsinstallversion stripped down to 3 characters to input into upgrade script. Can retrieve via grep web.xml
	#for now, just rely on user input for vpmsoldversion and vpmsinstallversion
	#done: currently only single version increments are supported.
	#todo: retrieve installed version automatically - from installed webapp.
	echo
	until mysql -u $dbuser -p$dbuserpass $dbname  -e ";" ; do
	       echo "Can't connect to mysql database, please enter your database credentials:"
	echo 
	echo Please enter your existing database name:;read dbname && export dbname=$dbname;clear
	sleep 1
	echo Please enter your database username:;read dbuser&&export dbuser=$dbuser;clear
	echo Please enter $dbuser\'s password:;read dbuserpass&&export dbuserpass=$dbuserpass;clear
	sleep 1
	done
	clear
	echo Please enter your current OpenVPMS version number and press Enter: 
	read vpmsoldversion
	#echo using current install version $vpmsoldversion and upgrading to $vpmsinstallversion 
	clear
	echo I can create a backup copy of your database. This will be stored in directory /home/backups_`hostname -s`
	echo To prevent this enter NO, or press Enter to continue.;read input
	case $input in
	NO)
	;;
	*)
	    mkdir -p /home/backups_`hostname -s`
	    ionice -c 3 /usr/bin/mysqldump --default-character-set=utf8 -u $dbuser -p$dbuserpass $dbname | gzip -9 > /home/backups_`hostname -s`/$dbname-$vpmsoldversion-`date +%A`.sql.gz || echo unable to create backup 
	;;
	esac

	preparevpmsinstaller
	export strippedinstallversion=`echo $vpmsinstallversion |sed 's/1//2'|sed 's/\.//2'`          	|| exit 12
	export maxmigratescript=`echo " $strippedinstallversion - .1"|bc -l`				|| exit 13
	export strippedoldversion=`echo $vpmsoldversion |sed 's/1//2'|sed 's/\.//2'`			|| exit 14
	echo upgrading database to release version $vpmsinstallversion.
	#dbmigrate needs to run after webapp configuration:
	dbmigrate
	#old: mysql -u $dbuser -p$dbuserpass $dbname  < $vpmsinstallerdir/update/db/migrate-$strippedoldversion-to-${strippedinstallversion}.sql  > /dev/null || echo ERROR UPGRADING YOUR DATABASE.; sleep 10
	#todo: backup old webapp
	#todo: run archload.sh here too, as required by various upgrades.
	cd $vpmsinstallerdir/bin/ && ./archload.sh >/dev/null &&echo archload.sh complete.  || echo ERROR RUNNING ARCHLOAD.sh

}

installlibreofficescript () {
#DISABLED, no longer requried: 
break
    wget http://easy-openvpms-installer.thevillagevet.co/libreoffice.sh -O /tmp/libreoffice.sh.new && mv /tmp/libreoffice.sh.new /etc/init.d/libreoffice.sh && chmod +x /etc/init.d/libreoffice.sh
    #take care of crashy libreoffice instance:
    grep libreoffice.sh /var/spool/cron/crontabs/root > /dev/null || echo "*/5 * * * * pstree|grep -q soffice  || /etc/init.d/libreoffice.sh start" >> /var/spool/cron/crontabs/root
}

resetrootdbpass () {
	#DISABLED: needs testing to work with bionic and newer.
	break

	#clear;echo "Please set a MYSQL root password on the following screen. Don't forget this password!";echo Press Enter to continue.;read input
	#rm -f /var/lib/mysql/ib_logfile*  #bug in initial Debian installer?
	#/etc/init.d/mysql restart
	gimme netcat-openbsd 
	if nc -z -v -w2 localhost 3306 ; then
	#connection is alive.
	    #this doesn't work with Official MySQL Community packages, only debian packages: dpkg-reconfigure mysql-server-$mysqlversion
	    #old, works on Jessie: 
    	case `lsb_release -sc` in
	jessie)
	    dpkg-reconfigure mysql-server-$mysqlversion
	    ;;
	stretch|bionic)
	    #new: 5.7.5 and later have new password syntax and no default root password for new installations.
	    #echo Press enter to reset the mysql password.; read input
	    systemctl stop mysqld.service
	    killall -9 mysqld 
	    #rm -f /var/run/mysqld/*
	    mkdir -p /var/run/mysqld
	    chown mysql:mysql /var/run/mysqld
	    /usr/sbin/mysqld --skip-grant-tables --skip-networking  --user=mysql &
	    sleep 3
	    #nc can't be used as networking disabled: if nc -z -v -w2 localhost 3306 ; then
		echo Setting mysql root user password to $rootdbpass
		#troublesome: echo "FLUSH PRIVILEGES;" | mysql -u root && \
		# The MySQL server is running with the --skip-grant-tables option so it cannot execute this statement -> 
		#newer syntax: echo "use mysql;ALTER USER 'root'@'localhost' IDENTIFIED BY $rootdbpass;" | mysql -u root && \
		#mariadb 10.1 syntax: 
		#old: echo "use mysql;update user set password=PASSWORD($rootdbpass) where User='root';"|mysql -u root
		#remove pass? UPDATE mysql.user SET authentication_string=PASSWORD('') WHERE User='root'

		echo "FLUSH PRIVILEGES;" | mysql -u root 
	    #else
#		echo Error starting mysql process with skip-grant-tables.
#		echo /usr/sbin/mysqld --skip-grant-tables --skip-networking  --user=mysql  
#		echo Press enter to exit and view the error log.;read input
#		grep ERROR /var/log/mysql/error.log |tail -n 10
#		/etc/init.d/mysql start 
#		exit
	    #fi
	    #/usr/sbin/mysqld --skip-grant-tables --skip-networking  --user=mysql --init-file=$file1 &
	    #doesn't work for the above: /etc/init.d/mysql stop && \
	    killall -9 mysqld && sleep 1 && systemctl start mysqld || exit
	    #echo Successfully set mysql root user password to $rootdbpass
	    sleep 1
	;;
	esac

	else
	    #connection is dead.
	    /etc/init.d/mysql start ||  \
	    echo mysql server failed! && exit
	fi
	
	#clear;echo "Please enter your newly created mysql password:" ;read rootdbpass
	#todo: automate this..

	#  rootdbpass=`< /dev/urandom tr -dc _A-Z-a-z-0-9 | head -c15;echo;`
	#doesn't work with mariadb: dpkg-reconfigure mysql-server mysql-server-$mysqlversion	||	dpkg-reconfigure mysql-server mysql-server-$mysqlversion	
	#systemctl stop mysql ; systemctl stop mariadb > /dev/null 2>&1
	#/etc/init.d/mysql stop
	#kill -9  `cat /var/run/mysqld/mysqld.pid`	 

	#mysqld_safe --skip-grant-tables --skip-networking &
	#todo: detect installed mysql version, then choose correct option:
	#For MySQL 5.7.6 and newer as well as MariaDB 10.1.20 and newer, use the following command.
 	#echo "FLUSH PRIVILEGES;" | mysql -u root
	#    echo "ALTER USER 'root'@'localhost' IDENTIFIED BY '$rootdbpass';" | mysql -u root  || exit

	#echo I will set the root password to $rootdbpass, while user dbuserpass is $dbuserpass.
	#echo press enter to continue;read input 
	#For MySQL 5.7.5 and older as well as MariaDB 10.1.20 and older, use:
	#	echo Setting mysql password.
	#     	echo "SET PASSWORD FOR 'root'@'localhost' = PASSWORD('${rootdbpass}');FLUSH PRIVILEGES;" > /dev/shm/temp154 ; chmod 600 /dev/shm/temp154;chown mysql /dev/shm/temp154
	#	echo starting mysqld in safe mode.
#		echo `which mysqld` --init-file=/dev/shm/temp154 --skip-networking --user=mysql  
#		`which mysqld` --init-file=/dev/shm/temp154 --skip-networking --user=mysql  &
#	     echo Wait a few moments.;sleep 10;sync
 #	rm -f /dev/shm/temp154
#	kill -9 `cat /var/run/mysqld/mysqld.pid` 
#	/etc/init.d/mysql restart
#	echo Continuing.
	#kill `cat /var/run/mysqld/mysqld.pid` ; kill `/var/run/mariadb/mariadb.pid` >/dev/null 2>&1
	#start with new password: 
	 #systemctl start mysql ;  systemctl start mariadb >/dev/null 2>&1 /etc/init.d/mysql start >/dev/null 2>&1

}	   

gimme () {
for z in "$*"; do
    DEBIAN_FRONTEND=noninteractive
    if which dpkg-query >/dev/null
    then        
        if ! dpkg-query -W -f='${Status}' $z 2>/dev/null | grep -q ok\ installed 
          then
	   echo installing $z
           apt-get -q install -y --allow-unauthenticated  $z
        fi
    fi

    if `which opkg` ; then
	if ! opkg list-installed|grep -q wget ; then
	  opkg update;opkg install  wget 
	fi
    fi
done
}


createnewdb () {
    #check the mysql connection is alive 
    systemctl start mysql.service
    if ! mysql -u root   -e  ";" ;  then
		echo unable  to connect as user root with no password. Exiting.
		exit
		#note: Stretch and newer do not set a mariadb or mysql-5.7 root password!
    fi 
   #set new database character set to utf8:
cat << 'EOF' > /tmp/1.cat
CREATE DATABASE `openvpms` /*!40100 DEFAULT CHARACTER SET utf8 */;
EOF
    sed -i "s/openvpms/${dbname}/g" /tmp/1.cat || exit
    #create the database and don't continue if it errors: 
    clear
#old: if `mysql -u root -p$rootdbpass -e ";" `; then
if `mysql -u root -e ";" `; then
    if ! cat /tmp/1.cat | mysql -u root ; then
	echo "Unable to create new database $dbname"
	echo "Press Ctrl-C to exit, or Enter to continue."
	read input
    fi
#old: 
fi

    #check the mysql connection to the new database: 
    if ! mysql -u root -p$rootdbpass  -e "use $dbname;" ; then
    	echo unable to connect to database server, continuing; sleep 5
    fi
    
    #mysql 5.7.6 and later have new create user syntax in two steps - you must include IDENTIFIED BY in both steps:
    if echo CREATE USER \'${dbuser}\'@\'localhost\' IDENTIFIED BY \'$dbuserpass\'\; | mysql -u root  ; then
       #step two:
       #debug:
       if echo GRANT ALL PRIVILEGES ON $dbname.\* TO \'$dbuser\'@\'localhost\' IDENTIFIED BY \'$dbuserpass\'\; | mysql -u root; then
       	clear;echo Database user created with privileges.
       else
	echo Unable to assign privileges to database user
	exit 1
       fi
    else
    	echo Unable to create the user.
	exit 1
    fi
   #mysql 5.7 and older: 
    #newer than stretch: if ! echo "GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost' IDENTIFIED BY '${dbuserpass}'; " | mysql -u root ; then
    #stretch in 2 lines:
    #echo "debug: CREATE USER ${dbuser}@localhost IDENTIFIED BY '${dbuserpass}'; COMMIT; | mysql -u root"
    #works for mariadb: echo "CREATE OR REPLACE USER '${dbuser}'@'localhost' IDENTIFIED BY '${dbuserpass}'; COMMIT;" | mysql -u root  && \
    #mariadb: if `echo "CREATE USER ${dbuser}@localhost IDENTIFIED BY '${dbuserpass}' ; COMMIT;" | mysql -u root  `; then
    #mariadb:  	echo Created database user $dbuser.
 #mariadb:     else
 #mariadb: 	echo Unable to create $dbuser, exiting.
 #mariadb: 	exit 1
 #mariadb:     fi
    #caution with use of single quote ' around dbname:
    #works with mariadb in stretch: echo "GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';COMMIT;" | mysql -u root 
 #mariadb:     echo "GRANT ALL PRIVILEGES ON ${dbname}.* TO '${dbuser}'@'localhost';COMMIT;" | mysql -u root  && \ 
 #mariadb:     	echo Assigned database privileges to database $dbname. || echo Error: unable to create database user!
    #and check that our user permissions stuck:
    if mysql -u $dbuser -p$dbuserpass -e "use $dbname;" ; then
      echo "database created successfully."
    else
      echo The automatically generated user cannot use the database!
      echo        mysql -u $dbuser -p$dbuserpass -e "use $dbname;"    
      echo 	  failed.
      exit
    fi

#create new database tables:
case $vpmsinstallversion in
1*|2.0*)
    mysql -u $dbuser -p$dbuserpass $dbname < $vpmsinstallerdir/db/db.sql || exit
;;
2.1*)
    cd $vpmsinstallerdir/bin/ && \
    	if ! ./dbtool --create install -u $dbuser -p$dbuserpass ; then
	    #note: dbtool doesn't use error exit status making the following redundant:
	    echo dbtool failed, exiting.
	    exit 1
	fi
;;
esac
    clear;echo dataload setup...
    #populate the database with some default data and an $webappuser with password as per $dbuserpass
    cd $vpmsinstallerdir/bin/ &&\
    if ! ./dataload.sh setup > /dev/null ; then
    	echo dataload failed, exiting. 
	exit 1
    fi
    clear;
    clear;echo loading Archetypes
    cd $vpmsinstallerdir/bin/ && until ./archload.sh > /dev/null ; do echo archload.sh failed to run, trying again in 30 seconds ; sleep 30; done
    #security roles: 
    clear;echo Installing Security Roles
    cd $vpmsinstallerdir/bin/ && ./dataload.sh -f ../import/data/roles.xml && echo OK. || echo There was an error installing roles.
    addons
}

addons () {
case $selection in
#if newinstall is selected, these questions should be skipped...
newinstall)
    choices="templates codes reminders postcodes"
;;
jdbctest)
    #speed up install while testing for jdbctest:
    choices=""
;;
*)
    DIALOG=${DIALOG-dialog}
    tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
    trap "rm -f $tempfile" 0 1 2 5 15
    $DIALOG \
	--backtitle "OpenVPMS Installer" \
	--title "Recommended Components" \
	--clear --no-cancel --ok-label "Next" \
	--checklist "Please select items to install:" 0 0 4 \
	"templates" "Useful templates, including invoice and receipts"  ON \
	"codes" "The standardised Veterinary Nomenclature codes" ON \
	"reminders" "Some example reminders to get you started" ON \
	"postcodes" "Australian Postcodes" ON \
	"SSLPREP"  "Still in testing: configure a TLS Certificate (requires a valid domain name pointing to this host)" OFF  2> $tempfile
    retval=$?
    choices=`cat $tempfile`
    case $retval in
      0)
	echo "'$choices' was selected"
      ;;
      1)
	echo "Cancel pressed."
	exit
      ;;
      255)
	echo "ESC pressed."
	exit
      ;;
    esac
;;
esac
for i in $choices; do $i;done
}

templates () {
echo "Installing default templates, such as invoices and receipts" 
for z in reports documents; do 
    cd $vpmsinstallerdir/bin/ &&\
    ./templateload $z $papersize > /dev/null||echo Failed to load $z in size $papersize.
done
    #old: cd $vpmsinstallerdir/bin/ && ./templateload ../reports/templates-"$papersize".xml > /dev/null||echo These papersizes failed to install
}
codes () {
    cd $vpmsinstallerdir/bin/ && ./dataload.sh -d ../import/data/VeNom  > /dev/null ||echo These codes failed to install && sleep 10
}

reminders () {
    cd $vpmsinstallerdir/bin/ && ./dataload.sh -f ../import/data/demo/reminders.xml  > /dev/null ||echo These reminders failed to install && sleep 10
}
postcodes () {
    cd $vpmsinstallerdir/bin/ && ./dataload.sh -f ../import/data/postcodesAU.xml > /dev/null ||echo These postcodes failed to install && sleep 10
}

configuretcusers () {
    #configure Tomcat users: 
    #this should be automatic: 
    #while : ; do echo configure tomcat management user
    #read -p "I can configure your tomcat management user for you, using randomly generated credentials. Would you like to to apply these to your tomcat configuration? (Y/n)" yesno
    #case $yesno in
    #[Nn]* ) echo OK, continuing
    #break
    #;;
    #* )
    echo "<tomcat-users>
    <user username=\"${tcusername}\" password=\"${tcpass}\" roles=\"manager-gui,admin-gui\"/>
    </tomcat-users> " > /etc/tomcat${tcversion}/tomcat-users.xml
    #echo "press enter to restart Tomcat"
    #read input
    service tomcat$tcversion restart || echo "There was an error; please check your /etc/${tcversion}/server.xml and /etc/default/tomcat$tcversion files are suitable"
    #break
    #;;
    #esac
    #done
}

localeconfiguration () {
    #automatic if locale file is not already present: 
    #todo: a newinstall should add sensible defaults; caution with HK installations!
    if ! [ -f /etc/default/locale ] ; then
	locale1=en_AU.UTF-8
	locale2=en_HK:en
	#echo I will set the default locale to $locale1 . You can modify this using dpkg-reconfigure locales after installation.
	#echo Please press enter to continue; read input
	gimme locales
	echo "LANG=\"$locale1\"
	LANGUAGE=\"$locale2\"" > /etc/default/locale
    fi
    clear
}

configuretomcatserver () {
case $selection in
#if newinstall is selected, these questions should be skipped...
newinstall|jdbctest)
    choice=0
;;
*)
    msg1="Do you wish me configure your Tomcat Server?"
    title="Tomcat Web Application Server Configuration"
    DIALOG=${DIALOG-dialog}
    tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
    trap "rm -f $tempfile" 0 1 2 5 15
    $DIALOG --backtitle "OpenVPMS Installer" --clear \
	--title "$title" \
	--yesno "`echo $msg1`" 0 0  2> $tempfile
    choice=$?
;;
esac
case $choice in
    0) echo Installing...
    cp /etc/default/tomcat$tcversion /etc/default/tomcat${tcversion}.bak
    #overwrite Debian's too conservative default xMx setting. 
    #tomcat defaults to limiting itself to using 25% of available RAM. Debian limits it to 128MB - far too little for OpenVPMS.
    #You can set it or use the sensible default: 
    #disabled for tomcat8: 
    		sed -i 's/-Xmx128m//g' /etc/default/tomcat7 > /dev/null 2>&1
	#enable log rotation and compression:
    	sed -i 's/\#LOGFILE_DAYS=14/LOGFILE_DAYS=4/g' /etc/default/tomcat$tcversion > /dev/null 2>&1
    	sed -i 's/\#LOGFILE_COMPRESS/LOGFILE_COMPRESS/g' /etc/default/tomcat$tcversion > /dev/null 2>&1
    
    cp /etc/tomcat$tcversion/server.xml /etc/tomcat$tcversion/server.xml.bak 

    #tomcat7 server.xml with TLS: 
  case $tcversion in
  7)
    echo "<?xml version='1.0' encoding='utf-8'?>
    <Server port='8005' shutdown='SHUTDOWN'>
     <Listener className='org.apache.catalina.core.JasperListener' />
     <Listener className='org.apache.catalina.core.JreMemoryLeakPreventionListener' />
     <Listener className='org.apache.catalina.mbeans.GlobalResourcesLifecycleListener' />
     <Listener className='org.apache.catalina.core.ThreadLocalLeakPreventionListener' />
     <GlobalNamingResources>
     <Resource name='UserDatabase' auth='Container'
     type='org.apache.catalina.UserDatabase'
     description='User database that can be updated and saved'
     factory='org.apache.catalina.users.MemoryUserDatabaseFactory'
     pathname='conf/tomcat-users.xml' />
     </GlobalNamingResources>
     <Service name='Catalina'>
     <Connector port='8080' protocol='HTTP/1.1'
     connectionTimeout='20000'
     URIEncoding='UTF-8'
     redirectPort='8443' />
    <Connector port='8443' protocol='HTTP/1.1' SSLEnabled='true'
     maxThreads='250' scheme='https' secure='true'
	     keystoreFile='/etc/letsencrypt/tomcat_keystore.pfx' keystorePass='REPLACEMEWITHSEDPASSWD'
			     clientAuth='false' sslProtocol='TLS' 
    useBodyEncodingForURI='true' 
     compressableMimeType='text/html,text/xml,text/css,text/javascript,text/plain' 
     compression='on'
	     compressionMinSize='2048' 
			     noCompressionUserAgents='gozilla, traviata'
					     />
     <Engine name='Catalina' defaultHost='localhost'>
     <Realm className='org.apache.catalina.realm.LockOutRealm'>
     <Realm className='org.apache.catalina.realm.UserDatabaseRealm'
     resourceName='UserDatabase'/>
     </Realm>
     <Host name='localhost' appBase='webapps'
     unpackWARs='true' autoDeploy='true'>
     <Valve className='org.apache.catalina.valves.AccessLogValve' directory='logs'
     prefix='localhost_access_log.' suffix='.txt'
     pattern='%h %l %u %t &quot;%r&quot; %s %b' />
     </Host>
     </Engine>
     </Service>
    </Server>" > /etc/tomcat$tcversion/server.xml
    ;;
    8|9)
	#todo: add TLS settings for version 8, so tckeys.sh is not required.
    echo '<?xml version="1.0" encoding="UTF-8"?>
<Server port="8005" shutdown="SHUTDOWN">
  <Listener className="org.apache.catalina.startup.VersionLoggerListener" />
  <!-- Security listener. Documentation at /docs/config/listeners.html
  <Listener className="org.apache.catalina.security.SecurityListener" />
  -->
  <!--APR library loader. Documentation at /docs/apr.html -->
  <Listener className="org.apache.catalina.core.AprLifecycleListener" SSLEngine="on" />
 <!-- Prevent memory leaks due to use of particular java/javax APIs-->
  <Listener className="org.apache.catalina.core.JreMemoryLeakPreventionListener" />
  <Listener className="org.apache.catalina.mbeans.GlobalResourcesLifecycleListener" />
  <Listener className="org.apache.catalina.core.ThreadLocalLeakPreventionListener" />

  <!-- Global JNDI resources
       Documentation at /docs/jndi-resources-howto.html
  -->
  <GlobalNamingResources>
    <!-- Editable user database that can also be used by
         UserDatabaseRealm to authenticate users
    -->
    <Resource name="UserDatabase" auth="Container"
              type="org.apache.catalina.UserDatabase"
              description="User database that can be updated and saved"
              factory="org.apache.catalina.users.MemoryUserDatabaseFactory"
              pathname="conf/tomcat-users.xml" />
  </GlobalNamingResources>

  <!-- A "Service" is a collection of one or more "Connectors" that share
       a single "Container" Note:  A "Service" is not itself a "Container",
       so you may not define subcomponents such as "Valves" at this level.
       Documentation at /docs/config/service.html
   -->
  <Service name="Catalina">

    <!--The connectors can use a shared executor, you can define one or more named thread pools-->
 <Executor name="tomcatThreadPool" namePrefix="catalina-exec-"
        maxThreads="250" minSpareThreads="4"/>
    -->


    <!-- A "Connector" represents an endpoint by which requests are received
         and responses are returned. Documentation at :
         Java HTTP Connector: /docs/config/http.html
         Java AJP  Connector: /docs/config/ajp.html
         APR (HTTP/AJP) Connector: /docs/apr.html
         Define a non-SSL/TLS HTTP/1.1 Connector on port 8080
    -->
    <Connector port="8080" protocol="HTTP/1.1"
               connectionTimeout="20000"
               redirectPort="8443" />
    <!-- A "Connector" using the shared thread pool-->
    <!--
    <Connector executor="tomcatThreadPool"
               port="8080" protocol="HTTP/1.1"
               connectionTimeout="20000"
               redirectPort="8443" />
    -->
    <!-- Define a SSL/TLS HTTP/1.1 Connector on port 8443
         This connector uses the NIO implementation. The default
         SSLImplementation will depend on the presence of the APR/native
         library and the useOpenSSL attribute of the
         AprLifecycleListener.
    Either JSSE or OpenSSL style configuration may be used regardless of
         the SSLImplementation selected. JSSE style configuration is used below.
    -->
    <!--
    <Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
               maxThreads="250" SSLEnabled="true">
        <SSLHostConfig>
            <Certificate certificateKeystoreFile="conf/localhost-rsa.jks"
                         type="RSA" />
        </SSLHostConfig>
    </Connector>
    -->
    <!-- Define a SSL/TLS HTTP/1.1 Connector on port 8443 with HTTP/2
         This connector uses the APR/native implementation which always uses
         OpenSSL for TLS.
         Either JSSE or OpenSSL style configuration may be used. OpenSSL style
         configuration is used below.
    -->

    <Connector port="8443" protocol="org.apache.coyote.http11.Http11AprProtocol"
               maxThreads="250" SSLEnabled="true" >
        <UpgradeProtocol className="org.apache.coyote.http2.Http2Protocol" />
        <SSLHostConfig>
            <Certificate certificateKeyFile="/opt/puppets-keys/letsencrypt/live/openvpms.thevillagevet.co/privkey.pem"
                         certificateFile="/opt/puppets-keys/letsencrypt/live/openvpms.thevillagevet.co/cert.pem"
                         certificateChainFile="/opt/puppets-keys/letsencrypt/live/openvpms.thevillagevet.co/fullchain.pem"
                         type="RSA" />
        </SSLHostConfig>
   </Connector>

    <!-- Define an AJP 1.3 Connector on port 8009 -->
    <!--
    <Connector port="8009" protocol="AJP/1.3" redirectPort="8443" />
    -->


    <!-- An Engine represents the entry point (within Catalina) that processes
         every request.  The Engine implementation for Tomcat stand alone
         analyzes the HTTP headers included with the request, and passes them
         on to the appropriate Host (virtual host).
         Documentation at /docs/config/engine.html -->

    <!-- You should set jvmRoute to support load-balancing via AJP ie :
    <Engine name="Catalina" defaultHost="localhost" jvmRoute="jvm1">
    -->
    <Engine name="Catalina" defaultHost="localhost">

      <!--For clustering, please take a look at documentation at:
          /docs/cluster-howto.html  (simple how to)
          /docs/config/cluster.html (reference documentation) -->
      <!--
      <Cluster className="org.apache.catalina.ha.tcp.SimpleTcpCluster"/>
      -->

      <!-- Use the LockOutRealm to prevent attempts to guess user passwords
        via a brute-force attack -->
      <Realm className="org.apache.catalina.realm.LockOutRealm">
        <!-- This Realm uses the UserDatabase configured in the global JNDI
             resources under the key "UserDatabase".  Any edits
             that are performed against this UserDatabase are immediately
             available for use by the Realm.  -->
        <Realm className="org.apache.catalina.realm.UserDatabaseRealm"
               resourceName="UserDatabase"/>
      </Realm>

      <Host name="localhost"  appBase="webapps"
            unpackWARs="true" autoDeploy="true">

        <!-- SingleSignOn valve, share authentication between web applications
             Documentation at: /docs/config/valve.html -->
        <!--
        <Valve className="org.apache.catalina.authenticator.SingleSignOn" />
        -->

        <!-- Access log processes all example.
             Documentation at: /docs/config/valve.html
             Note: The pattern used is equivalent to using pattern="common" -->
        <Valve className="org.apache.catalina.valves.AccessLogValve" directory="logs"
               prefix="localhost_access_log" suffix=".txt"
               pattern="%h %l %u %t &quot;%r&quot; %s %b" />

      </Host>
    </Engine>

  </Service>
</Server>

' > /etc/tomcat$tcversion/server.xml

    ;;
    *)
    #don't touch
    ;;
    esac
    #echo "press enter to restart Tomcat"
    #read input
    service tomcat$tcversion restart || echo "There was an error; please check your /etc/${tcversion}/server.xml and /etc/default/tomcat$tcversion files are suitable"

    ;;
    esac
}

cleanuptmpdirsdisabled () {
#disabled: the installer directory should not be deleted. The directory contains plugins and tools such as docload.
title=Cleanup
msg1="Shall I leave the downloaded copy of the installer on disk? Press No to delete it and tidy up the temporary files".
DIALOG=${DIALOG-dialog}
$DIALOG --backtitle "OpenVPMS Installer" --clear \
    --title "$title" --ok-label "Finish" \
    --yesno "`echo $msg1`" 0 0  
case $? in
  0)
  ;;
esac
}

webappconfigure () {
    if [ -z ${webappinstalldir+x} ]; then echo "webappinstalldir is unset!";exit 1; fi
    if [ -z ${webapptmpdir+x} ]; then echo "webapptmpdir is unset!";exit 1; fi
    echo Extracting the webapp file to directory $webapptmpdir for clinic $clinicname
    mkdir  -p $webapptmpdir 
    if cd $webapptmpdir/ ;then
    	if unzip -u -d $webapptmpdir $vpmsinstallerdir/webapps/openvpms.war >/dev/null;then
		echo webapp extracted.
	else
		echo error extracting war file, exiting.
		exit 1
	fi
    fi
    #tomcat detects the new webapp and automatically deploys it. This is faster than restarting tomcat.
    #replace the WebAppKey (directory name) with correct value:
    echo Updating web.xml parameters.
    sed -i "s/<param-value>openvpms</<param-value>openvpms_$clinicname</g" $webapptmpdir/WEB-INF/web.xml   || exit
    #echo modifying $webapptmpdir/WEB-INF/web.xml to change description field adding ${vpmsinstallversion}
    sed -i "s/<display-name>OpenVPMS</<display-name>OpenVPMS${vpmsinstallversion}</g" $webapptmpdir/WEB-INF/web.xml   || exit
    #sed -i "s/<description>OpenVPMS/<description>OpenVPMS${vpmsinstallversion}/g" $webapptmpdir/WEB-INF/web.xml
    
modifyhibernateproperties 
}

modifyhibernateproperties () {
case $vpmsinstallversion in
2.1*)
    #webapp copy:
    echo "
    jdbc.driverClassName=com.mysql.jdbc.Driver
    jdbc.url=jdbc:mysql://localhost:3306/$dbname?useSSL=false
    jdbc.username=$dbuser
    jdbc.password=$dbuserpass
    hibernate.reportingconnection.url=jdbc:mysql://localhost:3306/$dbname
    hibernate.reportingconnection.username=$dbuser
    hibernate.reportingconnection.password=$dbuserpass
    " > $webapptmpdir/WEB-INF/classes/hibernate.properties
    #for dbtool connection:
    echo "
    jdbc.driverClassName=com.mysql.jdbc.Driver
    jdbc.url=jdbc:mysql://localhost:3306/$dbname?useSSL=false
    jdbc.username=$dbuser
    jdbc.password=$dbuserpass
    hibernate.reportingconnection.url=jdbc:mysql://localhost:3306/$dbname
    hibernate.reportingconnection.username=$dbuser
    hibernate.reportingconnection.password=$dbuserpass
    " > $vpmsinstallerdir/conf/hibernate.properties
;;
1*|2.0*)
#modify hibernate.properties:
    echo "
    hibernate.dialect=org.hibernate.dialect.MySQL5InnoDBDialect
    hibernate.connection.driver_class=com.mysql.jdbc.Driver
    hibernate.connection.url=jdbc:mysql://${dbhost}:3306/${dbname}
    hibernate.connection.username=${dbuser}
    hibernate.connection.password=${dbuserpass}
    hibernate.reportingconnection.url=jdbc:mysql://${dbhost}:3306/$dbname
    hibernate.reportingconnection.username=${dbuser}
    hibernate.reportingconnection.password=${dbuserpass}
    hibernate.show_sql=false
    hibernate.max_fetch_depth=4
    hibernate.c3p0.min_size=5
    hibernate.c3p0.max_size=20
    hibernate.c3p0.timeout=1800
    hibernate.c3p0.max_statements=50
    hibernate.query.factory_class=org.hibernate.hql.ast.ASTQueryTranslatorFactory
    hibernate.jdbc.batch_size=30
    hibernate.cache.provider_class=org.hibernate.cache.SingletonEhCacheProvider
    hibernate.cache.use_second_level_cache=true
    hibernate.cache.use_query_cache=true
    " > $webapptmpdir/WEB-INF/classes/hibernate.properties
    #for dbtool's connection:
    echo "
    jdbc.driverClassName=com.mysql.jdbc.Driver
    #version 8 uses: jdbc.driverClassName=com.mysql.cj.jdbc.Driver
    jdbc.url=jdbc:mysql://localhost:3306/$dbname
    jdbc.username=$dbuser
    jdbc.password=$dbuserpass
    " > $vpmsinstallerdir/conf/hibernate.properties
;;
esac
chmod 700 $vpmsinstallerdir/conf/hibernate.properties
#logs and sessions: 
    sed -i "s/openvpms-full.log/$clinicname.log-full/g" $webapptmpdir/WEB-INF/classes/log4j.properties || exit
    sed -i "s/openvpms.log/$clinicname.log/g" $webapptmpdir/WEB-INF/classes/log4j.properties  || exit
    #decrease log verbosity:
    #sed -i "/log4j.rootLogger/c\/log4j.rootLogger=SEVERE,\ fileout" $webapptmpdir/WEB-INF/classes/log4j.properties
    #clean out old security sessions:
    rm -fr /var/lib/tomcat$tcversion/work/Catalina/localhost/openvpms*

}

webappinstall () {
    if [ -z ${webappinstalldir+x} ]; then echo "var is unset!";exit 1;fi
    chown tomcat$tcversion $webapptmpdir -R 
    #move any old version out of the way: 
    mv  /var/lib/tomcat$tcversion/webapps/$webappdirname /tmp/openvpms${clinicname}.bak  >/dev/null 2>&1
    cp -aux  $webapptmpdir/* $webappinstalldir  && rm -fr $webapptmpdir/ 		|| exit 
    chown tomcat$tcversion /var/lib/tomcat$tcversion/webapps/$webappdirname/  -R    	|| exit
}

themeselect () {
#theme choices:
case $selection in
#if newinstall is selected, these questions could be skipped...
newinstall|jdbc)
    choice=green
;;
*)
    DIALOG=${DIALOG-dialog}
    tempfile=`tempfile 2>/dev/null` || tempfile=/dev/shm/test$$
    trap "rm -f $tempfile" 0 1 2 5 15
    $DIALOG \
	--backtitle "OpenVPMS Installer" \
	--title "Theme Selection" \
	--clear  --ok-label "Next" \
	--cancel-label "Exit" \
	--menu "Please select:" 0 0 4 \
	"1" "Green (the default theme)." \
	"2" "Silver grey (a low contrast theme)."  2> $tempfile
    retval=$?
    choice=`cat $tempfile`
    case $retval in
      0)
	echo "'$choice' was selected" ;sleep 1
      ;;
      1)
	echo "Cancel pressed."
	exit
      ;;
      255)
	echo "ESC pressed."
	exit
      ;;
    esac
;;
esac

case $choice in
      1)
	clinictheme=green
      ;;
      2)
	clinictheme=silvergrey
      ;;
    esac
    
    case $clinictheme in 
    silvergrey)
    #theme.colour: 989898 is a moderate grey: 
    sed -i "/theme.colour/c\theme.colour = '#989898'" $webapptmpdir/WEB-INF/classes/style/default.properties
    #all whites to light grey: 
    sed -i 's/ffffff/d5d5d5/g' $webapptmpdir/WEB-INF/classes/style/*
    sed -i "/theme.selection.colour/c\theme.selection.colour = '#989898'" $webapptmpdir/WEB-INF/classes/style/default.properties
    sed -i "/theme.colour/c\theme.colour = '#989898'" $webapptmpdir/WEB-INF/classes/style/default.properties
    sed -i "/theme.button.colour/c\theme.button.colour = '#989898'" $webapptmpdir/WEB-INF/classes/style/default.properties
    #todo: change white backgrounds in panes to d5d5d5
    #pane background is in default.stylesheet. All whites to light grey:
    sed -i 's/ffffff/d5d5d5/g' $webapptmpdir/WEB-INF/classes/style/default.stylesheet
    #various backgrounds are e1e1e1 by default: 
    sed -i 's/e1e1e1/d5d5d5/g' $webapptmpdir/WEB-INF/classes/style/default.stylesheet
    #default yellow selector is #ffff99 in default.stylesheet
    #default Bright Blue text is 0000ffA
    sed -i 's/0000ffA/989898/g'  $webapptmpdir/WEB-INF/classes/style/*
    #You need to use wildards (.*) before and after to replace the whole line:
    #sed 's/.*TEXT_TO_BE_REPLACED.*/This line is removed by the ./'
    ;;
    *|green)
    ;;
    esac
    case $clinicname in
    pulsevet)
    #modify colours: this is safer than trying to migrate default.properties file and so on between versions: 
    #pulsevet colors are purple / blue
    #Replace line theme.colour  = '#333366'
    # theme.title.colour with theme.title.colour = '#fdf5e6'
    #theme.button.colour with theme.button.colour = '#3399FF'
    #theme.selection.colour = '#336699'
    sed -i 's/339933/333366/g' $webapptmpdir/WEB-INF/classes/style/default.properties
    sed -i 's/ffffff/fdf5e6/g' $webapptmpdir/WEB-INF/classes/style/default.properties
    sed -i 's/99cc66/3399FF/g' $webapptmpdir/WEB-INF/classes/style/default.properties
    sed -i 's/85c1ff/336699/g' $webapptmpdir/WEB-INF/classes/style/default.properties
    ;;
    fourpaws)
    ;;
    esac
}


############## end define functions ###################

############## start argument specific cases ###################

case $1 in 
    addons)
	addons
    ;;
    newinstall|newclinic|jdbctest)
	setclinicname
	#can't detect base Centos version without executing this:
	if [ -e `which yum` ] ; then
	  yum install redhat-lsb-core.x86_64
	fi
	echo Installing OpenVPMS for $clinicname
	installrequiredsoftware   
	mysqlconfiguration 
	configuretomcatserver 
	preparevpmsinstaller
	webappconfigure
	localeconfiguration
	createnewdb
	laststeps
    ;;
    upgrade|update)
	setclinicname
	installrequiredsoftware
	mysqlconfiguration  
	configuretomcatserver 
	preparevpmsinstaller
	webappconfigure
	runupgrade
	laststeps
    ;;
    addclinic|addhospital)
	setclinicname
	installrequiredsoftware
	checkmysqlrootpass
	setclinicname
	echo Installing OpenVPMS $vpmsinstallversion for Clinicname $clinicname
	sleep 5
	preparevpmsinstaller
	webappconfigure
	createnewdb
	laststeps
    ;;
    preparevpmsinstaller)
	setclinicname
	preparevpmsinstaller
    ;;
    webappinstall)
	setclinicname
	preparevpmsinstaller
	webappconfigure
	laststeps
    ;;
    setclinicname)
	setclinicname
    ;;
    enablessl)
	setclinicname
	clear
	echo I can configure your Tomcat server for secure SSL/TLS communications.
	echo "However, you must already have a domain name (even a free one from https://freedns.afraid.org)"
	echo This script will restart any apache webserver if running.
	echo
	echo Press Enter to continue or Ctrl+C to exit.
	read input
	SSLPREP
    ;;
    checkvars)
	setclinicname
	checkvars
    ;;
    cnfont)
	setclinicname
	preparevpmsinstaller
	#modify fonts to ensure they print Chinese characters using font WenQuanYi Micro Hei :
	fontjar=wenquan-microhei.jar
	find $reportsdir -type f -print0 | xargs -0  sed -i 's/SansSerif/WenQuanYi\ Micro\ Hei/g'
	find $reportsdir -type f -print0 | xargs -0  sed -i 's/DejaVu\ Sans/WenQuanYi\ Micro\ Hei/g'
	#todo: check, is this resizing necessary with the WenQuanYi font??
	echo install templates for paper size $papersize
	cd $vpmsinstallerdir/bin/ && ./templateload ../reports/templates-"$papersize".xml > /dev/null && echo Success. ||echo These papersizes failed to install
	#cleanuptmpdirs
	cd /tmp && wget  -N -q https://easy-openvpms-installer.thevillagevet.co/$fontjar
	cp /tmp/$fontjar /usr/share/tomcat$tcversion/lib/
	#done: test whether simply copying the ttf and restarting Tomcat works: cp file.ttf /usr/lib/jvm/j*/jre/lib/fonts/  #doesn't work in Jessie
	clear
	echo You can also install this font on your desktop computer by downloading it from:
	echo "https://easy-openvpms-installer.thevillagevet.co/WenQuanYiMicroHei.ttf"
	echo or installing it with        apt-get install fonts-wqy-microhei
	echo Press Enter to continue
	read input
	clear;echo Press Enter to restart tomcat and enable this custom font.;read input
	service tomcat$tcversion restart
    ;;
    startscreen|*)
	startscreen
	exit
    ;;

esac

############## end argument specific cases ###################
