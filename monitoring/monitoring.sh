#!/bin/bash

#exit code
OK=0
WARNING=1
CRITICAL=2
UNKNOWN=3

API_PATH="" #change it
BASE_DIR="" #change it
MONITORING_DATA_DIR="${BASE_DIR}/data"
SUBMISSION_ID="SSUB000019"

ruby ${BASE_DIR}/monitoring.rb "${API_PATH}" "${MONITORING_DATA_DIR}" "${SUBMISSION_ID}"
#get exit code
STATUS=$?
case $STATUS in
  0)  echo "** OK **"
      exit $OK ;;
  1)  echo "** WARNING **"
      exit $WARNING ;;
  2)  echo "** CRITICAL **"
      exit $CRITICAL ;;
  *)  echo "** UNKNOWN **"
      exit $UNKNOWN ;;
esac
