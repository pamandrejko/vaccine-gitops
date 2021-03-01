#!/bin/bash
scriptDir=$(dirname $0)

##################
### PARAMETERS ###
##################




source ${scriptDir}/env.sh

###################################
### DO NOT EDIT BELOW THIS LINE ###
###################################
### EDIT AT YOUR OWN RISK      ####
###################################
ENVPATH=environments/event-streams
SA_NAME=vaccine-runtime
SCRAM_USER=scram-user
TLS_USER=tls-user

############
### MAIN ###
############
source ${scriptDir}/login.sh
### Login
# Make sure we don't have more than 1 argument
if [[ $# -gt 1 ]];then
 echo "Usage: sh  `basename "$0"` [--skip-login]"
 exit 1
fi

validateLogin $1

source ${scriptDir}/defineProject.sh

createProjectAndServiceAccount $YOUR_PROJECT_NAME $SA_NAME

echo "#####################################################"
echo "Create secret for topic name and bootstrap server URL"
echo "#####################################################"

KAFKA_BOOTSTRAP=$(oc get route -n ${KAFKA_NS} ${KAFKA_CLUSTER_NAME}-kafka-bootstrap -o jsonpath="{.status.ingress[0].host}:443")
if [[ -z $(oc get secret reefer-simul-secret) ]]
then
    oc create secret generic reefer-simul-secret --from-literal=KAFKA_BOOTSTRAP_SERVERS=$KAFKA_BOOTSTRAP --from-literal=KAFKA_MAIN_TOPIC=$YOUR_TELEMETRIES_TOPIC
fi
if [[ -z $(oc get secret reefer-monitoring-agent-secret) ]]
then
    oc create secret generic reefer-monitoring-agent-secret \
    --from-literal=TELEMETRY_TOPIC=$YOUR_TELEMETRIES_TOPIC \
    --from-literal=REEFER_TOPIC=$YOUR_REEFER_TOPIC \
    --from-literal=CP4D_USER=$YOUR_CP4D_USER \
    --from-literal=CP4D_API_KEY=$YOUR_CP4D_API_KEY \
    --from-literal=CP4D_AUTH_URL=$YOUR_CP4D_AUTH_URL \
    --from-literal=ANOMALY_DETECTION_URL=$ANOMALY_DETECTION_URL
fi

echo "#############"
echo "Define users" 
echo "#############"
source ${scriptDir}/defineUser.sh

if [[ -z $(oc get secret ${SCRAM_USER} -n ${KAFKA_NS}) ]]
then
    defineUser ${SCRAM_USER} ${KAFKA_CLUSTER_NAME} scram-user ${ENVPATH}
    # THERE IS A BUG in oc or kubectl kustomize that is not parsing the json
    # error: json: cannot unmarshal object into Go struct field Kustomization.patchesStrategicMerge of type patch.StrategicMerge
    oc apply -k  ${ENVPATH}/overlays -n ${KAFKA_NS}
    sleep 5
    
else
    echo "${SCRAM_USER} present"
fi
# As the project is personal to the user, we can keep a generic name for the secret
oc get secret ${SCRAM_USER} -n ${KAFKA_NS} -o json |  jq -r '.metadata.name="scram-user"' | jq -r '.metadata.namespace="'${YOUR_PROJECT_NAME}'"' | oc apply -f -

if [[ -z $(oc get secret ${TLS_USER} -n ${KAFKA_NS}) ]]
then
    defineUser ${TLS_USER} ${KAFKA_CLUSTER_NAME} tls-user ${ENVPATH}
    oc apply -k  $ENVPATH/overlays -n ${KAFKA_NS}
    sleep 5
    
else
    echo "${TLS_USER} present"
fi

# As the project is personal to the user, we can keep a generic name for the secret
oc get secret ${TLS_USER} -n ${KAFKA_NS} -o json | jq -r '.metadata.name="tls-user"' | jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -

if [[ -z $(oc get secret kafka-cluster-ca-cert) ]]
then
    oc get secret ${KAFKA_CLUSTER_NAME}-cluster-ca-cert -n ${KAFKA_NS} -o json | jq -r '.metadata.name="kafka-cluster-ca-cert"' |jq -r '.metadata.namespace="'${PROJECT_NAME}'"' | oc apply -f -
fi



echo "DEPLOY APPLICATION MICROSERVICES"
oc apply -k apps/cold-chain

### GET ROUTE FOR USER INTERFACE MICROSERVICE
echo "User Interface Microservice is available via http://$(oc get route oc vaccine-reefer-simulator -o jsonpath='{.status.ingress[0].host}')"


echo "#############"
echo "# Done ! "
echo "#############"
oc get pods 
echo "#############"
echo "When you are done with the lab do: ... ./scripts/deleteColdChain.sh" 
