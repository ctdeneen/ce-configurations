#!/bin/bash
#
# Gemini auto installer
#

source utils/functions.rc
source config.ini

for f in components/*.rc;do source $f;done


cat << EOL
  _  _     _    _   _____ _   _ ____      _    
 | |/ /   / \  | | |_   _| | | |  _ \    / \   
 | ' /   / _ \ | |   | | | | | | |_) |  / _ \  
 | . \  / ___ \| |___| | | |_| |  _ <  / ___ \ 
 |_|\_\/_/   \_\_____|_|  \___/|_| \_\/_/   \_\_
                                               
											   
EOL
printf "Gemini auto installer\n"
printf "Kaltura install version %s\n" "$(grep -o '[0-9].*' installer/version.ini)" | tee -a $logfile


usage () {
	printf "Usage: %s --archive <kaltura_archive_name>\n\t--pentaho <pentaho file>\n" "$0"
}

while :
do
    case $1 in
        -h | --help | -\?)
        	usage
		exit 0
		;;
	-a | --archive)
		archive_file=$2
		shift 2
		;;
	-p | --pentaho)
      		pentaho_file=$2
		shift 2
		;;
	*)
        	break
        	;;
    esac
done

# Verify configuration file, currently not checking anything due to constant changes
for var in log_file ;do
	if [ -z $var ];then
		printf "The setting %s is missing a value in config.ini\n" "$var" | tee -a $logfile
		exit 1
	fi
done

# Packages required for the installer to work, might want to speed this up by performing a check
printf "Installing base packages for the installer...\n" | tee -a $logfile
if ! yum -y install wget ed >> $logfile 2>&1;then
    printf "\e[00;31mError:\e[00mError: unable to install base software which is required by the auto installer\n" | tee -a $logfile
	exit 1
fi

cat << EOL

The following components will be installed
	
	Prerequisites: $prereq
	MySQL: $mysql
	NTP: $ntp
	Pentaho: $pentaho
	Kaltura: $kaltura
	Patches: $patches

Proceed?(y/n)
EOL
read answer
if [ $answer != 'y' ];then
	printf "Quitting\n" | tee -a $logfile
	exit 0
fi

#Install each component
# Pre-requisites
if [ $prereq == 'yes' ];then
	printf "Installing pre-requesisites\n" | tee -a $logfile
	if ! install_prereq; then
		exit 1
	fi
fi

# NTP server
if [ $ntp ==  'yes' ];then
	printf "Installing and configuring NTP server\n" | tee -a $logfile
	install_ntp
fi
	
# MySQL Server
# Option 1 install new MySQL server
if [ $mysql -eq '1' ];then
	printf "Installing and configuring MySQL\n" | tee -a $logfile
	# Generate new passwords for kaltura and etl users
	mysql_kaltura_password=$(</dev/urandom tr -dc A-Za-z0-9 | head -c15)
	mysql_etl_password=$(</dev/urandom tr -dc A-Za-z0-9 | head -c15)
	# Place those values into the config.ini file
	write_param mysql_kaltura_password $mysql_kaltura_password config.ini
	write_param mysql_etl_password $mysql_etl_password config.ini
	# Call the mysql installer
	if ! install_mysql;then
		exit 1
	fi
	# For the kaltura installer
	create_new_db=1

# Option 2 using existing server but install a new database
elif [ $mysql -eq '2' ];then
	printf "You specified an existing mysql server that doesn't contain a Kaltura database, checking connectivity\n" | tee -a $logfile
	# Test connectivity to the server
	if ! do_query "quit" &> /dev/null;then
		echo -e  "\e[00;31mError:\e[00m unable to connect to the database server $mysql_host" | tee -a $logfile
		exit 1
	else 
		echo -e "\e[00;32mSuccess!\e[00m"
	fi
	# Check to make sure that a Kaltura database doesn't already exist
	if do_query "use kaltura" &> /dev/null;then
		echo -e "\e[00;31mError:\e[00m a Kaltura database already exists on $mysql_host" | tee -a $logfile
		exit 1
	fi
	
	# Generate new passwords for kaltura and etl users
	mysql_kaltura_password=$(</dev/urandom tr -dc A-Za-z0-9 | head -c15)
	mysql_etl_password=$(</dev/urandom tr -dc A-Za-z0-9 | head -c15)
	# Place those values into the config.ini file
	write_param mysql_kaltura_password $mysql_kaltura_password config.ini
	write_param mysql_etl_password $mysql_etl_password config.ini
	
	# Set the option to create a new database	
	create_new_db=1

elif [ $mysql -eq '3' ];then
	printf "You specified an existing mysql server that contains a Kaltura database, checking connectivity\n" | tee -a $logfile
	# Test connectivity to the server
	if ! do_query "quit" &> /dev/null;then
		echo -e  "\e[00;33mWarning:\e[00m unable to connect to the database server $mysql_host" | tee -a $logfile
	else 
		echo -e "\e[00;32mSuccess!\e[00m"
	fi
	create_new_db=0
elif [ $mysql -eq '0' ];then
	printf "Mysql will not be installed\n"
else
	printf "\e[00;33mWarning:\e[00m invalid option for MySQL settings in configuration, this variable is required,skipping\n" | tee -a $logfile
fi

# Pentaho
if [ $pentaho == 'yes' ];then
    printf "Installing and configuring Pentaho\n" | tee -a $logfile
    if ! install_pentaho;then
        exit 1
    fi
fi

# Kaltura
if [ $kaltura == 'yes' ];then
	printf  "Installing and configuring Kaltura\n" | tee -a $logfile
	if ! install_kaltura;then
		exit 1
	fi
fi

# Patches
if [ $patches == 'yes' ];then
	printf "Applying Patches\n" | tee -a $logfile
	if ! install_patches;then
		printf "\e[00;33mWarning:\e[00m unable to apply some or all patches\n" | tee -a $logfile
	fi
fi

exit 0
