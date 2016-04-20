#!/bin/sh
echo "script called" > ./tmp/test_pl_echo.txt
env > ./tmp/test_pl_env.txt
perl ./validator/annotated_sequence_validator/ddbj_annotated_sequence_validator.pl ./tmp/sample01_WGS_PRJDB4174.json > ./tmp/test_pl_sh.json
