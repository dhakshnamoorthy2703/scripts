#!/bin/bash -e
#The actual host we want to deploy changes to
DEPLOY_HOST=$1

#Include common script of functions
. scripts/deploy_functions.sh

#Check number of active services
echo "[BUILDINFO] Checking number of active services"
set +e
ACTIVE_SERVICES_BEFORE_RESTART=$(curl -s -u ${DEPLOY_AUTH} ${DEPLOY_HOST}/console/text/list | grep -c "running")
set -e
echo $ACTIVE_SERVICES_BEFORE_RESTART

#Trigger Tomcat stop
echo "[BUILDINFO] Stopping Tomcat. Log will be redirected to ${WORKSPACE}/tomcat_stop_log.txt"
#Output is redirected to file as it will contain a load of "Loaded" lines from the classloader
#ssh -q -oStrictHostKeyChecking=no ${REMOTE_USER}@${DEPLOY_HOST} /sbin/service webserver-tomcat-1a stop > tomcat_stop_log.txt
custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} '/sbin/service webserver-tomcat stop' > tomcat_stop_log.txt

# Clean up log and tmp directories (should do this while Tomcat is stopped as this will prevent any file locks on open log files etc. from affecting the disk space measurement)
	#if this is cleaner done by calling a remote script, do that! Could split this script here (stop_tomcat and [re]start_tomcat.sh), and call the remote script from the job, to make it clearer that there is a dependency upon the script being copied to the Tomcat instance.

# empty remote lib folder first 
#echo "[BUILDINFO] Emptying custom libraries on Tomcat host"
#custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} 'rm -f /webserver/tomcat-1a/conf/app.d/lib/*'
# then rsync everything across
#echo "[BUILDINFO] Copying apache and tomcat config files and libraries from workspace to host"
#rsync -q -r --exclude="*.svn" --temp-dir="/tmp" --inplace -e "ssh -q -oStrictHostKeyChecking=no" default/ ${REMOTE_USER}@${DEPLOY_HOST}:/webserver
#The chmod below will "fail" but it will set perms on every file our user has right to, which is what we need.
set +e
custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} 'chmod -fR oug+rx /webserver/*'
set -e
#To create a symbolic link for cgi scripts
#custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} 'ln -sf devperf.tc /webserver/apache-1a/cgi-bin/devperf'

#Get current line number of log file (so we can later examine the log from this line number onwards)
DATE_PATH=`date +%Y-%m-%d`
echo "[BUILDINFO] Retrieving current line number of log file"
CATALINA_LOG_START_LINE=`custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} "cat ${TOMCAT_LOG_DIR}/catalina.\${DATE_PATH}" | wc -l`
echo $CATALINA_LOG_START_LINE

#Trigger Tomcat start
echo "[BUILDINFO] Starting Tomcat"
custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} '/sbin/service webserver-tomcat start'	

#Restart httpd too as this job will be triggered after config sync, which could touch httpd settings as well as tomcat
echo "[BUILDINFO] Restarting Apache"
custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} '/bin/apachectl stop'
custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} '/bin/apachectl start' | tee httpd_restart_log.txt
#Service command never fails...so need to grep logs for desired success message
cat httpd_restart_log.txt | grep -q 'apache instance webserver-apache is up'

#Wait for log saying server has started up (does this come after the server has attempted to start all services? Yes, seems so)
startup_not_finished() { ! custom_ssh ${REMOTE_USER} ${DEPLOY_HOST} "tail -n +${CATALINA_LOG_START_LINE} ${TOMCAT_LOG_DIR}/catalina.${DATE_PATH} | grep -E 'INFO: Server startup in.*'"; }

echo "[BUILDINFO] Starting Tomcat"
if run_function_until_false startup_not_finished 60 60 "for server to finish starting up";
then
	echo "[BUILDINFO] Server reporting that it started successfully"
else
	echo "[ERROR] Server failed to startup within the time limit"
	exit 1
fi

#Check number of active services
echo "[BUILDINFO] Checking number of active services"
ACTIVE_SERVICES_AFTER_RESTART=$(curl -s -u ${DEPLOY_AUTH} ${DEPLOY_HOST}/console/text/list | grep -c "running")
echo $ACTIVE_SERVICES_AFTER_RESTART

if [[ "$ACTIVE_SERVICES_AFTER_RESTART" -lt "$ACTIVE_SERVICES_BEFORE_RESTART" ]]
then
	echo "[ERROR] Restart Failed"
	echo "[ERROR] Number of active services: $ACTIVE_SERVICES_AFTER_RESTART vs. $ACTIVE_SERVICES_BEFORE_RESTART before restart"
	exit 1
else
	echo "[BUILDINFO] Restart Succeeded"
	echo "[BUILDINFO] Number of active services: $ACTIVE_SERVICES_AFTER_RESTART vs. $ACTIVE_SERVICES_BEFORE_RESTART before restart"
fi