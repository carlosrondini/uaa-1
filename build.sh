#!/bin/bash
#set -e

exit 0
apache_path=/home/work/uaa/apache-tomcat-6.0.36
cur_path=$(dirname $0)
cd $cur_path

if ! which mvn &>/dev/null
then
  echo "Error:please install mvn first, exit"
  exit 1
fi

#rm -rf uaa/target/*

mvn clean install 

if [[ ! -d $apache_path ]]
then
  echo "Apache path ${apache_path} doesn't exist, exit"
  exit 1
fi
rm -rf ${apache_path}/webapps/*
cp uaa/target/cloudfoundry-identity-uaa-*.war ${apache_path}/webapps/uaa.war

echo "All done"
exit 0
