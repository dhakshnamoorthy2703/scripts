#'Internal params'
APP_DEPLOY_PATH="/webserver/tomcat/appl"
LOGBACK_DEPLOY_PATH="/webserver/tomcat/conf/app.d"
TOMCAT_LOG_DIR="/webserver/tomcat/logs"
REMOTE_USER="wgadmin"

get_dependency_from_nexus()
{
	#Works for release versions only
	GROUPID=$1
    ARTIFACTID=$2
    VERSION=$3
    TYPE=$4
	GROUPFOLDERPATH=`echo ${GROUPID} | tr . /`
	ARTIFACT_URL="http://${NEXUS_URL}/nexus/content/groups/public/${GROUPFOLDERPATH}/${ARTIFACTID}/${VERSION}/${ARTIFACTID}-${VERSION}.${TYPE}"
    echo "[BUILDINFO] Attempting to download ${TYPE} file from ${ARTIFACT_URL}"
	STATUS_CODE=$(curl -w "%{http_code}" -o /dev/null -s -I -k -f "${ARTIFACT_URL}")
    if [[ ${STATUS_CODE} -ne 200 ]]
    then
        echo "[ERROR] Dependency not found in Nexus at ${ARTIFACT_URL}"
        return 1
    else
        echo "[BUILDINFO] Downloading ${TYPE} file from ${ARTIFACT_URL}"       
        if curl -s -k -f "${ARTIFACT_URL}" >> "${ARTIFACTID}-${VERSION}.${TYPE}";
        then
            return 0
        else
           	echo "[ERROR] Download from Nexus URL ${ARTIFACT_URL} failed"
            return 1
        fi
    fi
}

run_function_until_false() {
	FUNCTION=$1
	DELAY=$2
	LOOPS=$3
	TEXT=$4
	COUNT=0
	while $FUNCTION;
	do
			if [ "$COUNT" -eq "$LOOPS" ]
			then
				return 1
			fi
			echo "[BUILDINFO] Waiting for ${DELAY} seconds ${TEXT}"
			sleep $DELAY
			COUNT=$[$COUNT+1]
	done
}

custom_ssh() {
	local REMOTE_USER=$1
	local HOST=$2
	local COMMAND=$3
	ssh -q -oStrictHostKeyChecking=no ${REMOTE_USER}@${HOST} ${COMMAND}
}