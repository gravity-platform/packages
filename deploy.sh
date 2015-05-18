#!/bin/env bash

if [[ -f `pwd`/deploy.local.sh ]]; then
    . `pwd`/deploy.local.sh
fi

if [[ ! $APP_NAME ]]; then
    read -p "Enter app name: " APP_NAME
fi
if [[ ! $CF_API ]]; then
    read -p "Enter cloudfoundry API endpoint: " CF_API
fi
if [[ ! $CF_DOMAIN ]]; then
    read -p "Enter cloudfoundry DOMAIN: " CF_DOMAIN
fi
if [[ ! $CF_ORG ]]; then
    read -p "Enter cloudfoundry ORG: " CF_ORG
fi
if [[ ! $CF_SPACE ]]; then
    read -p "Enter cloudfoundry SPACE: " CF_SPACE
fi
if [[ ! $CF_USER ]]; then
    read -p "Enter cloudfoundry username: " CF_USER
fi
if [[ ! $CF_PASS ]]; then
    read -s -p "Enter cloudfoundry password: " CF_PASS
fi

ECHO_CMD=`which echo`

# suffix from $1 for app name
SUFFIX=${1:-""}
APP_NAME="${APP_NAME}${SUFFIX}"
APP_ROUTE="${APP_NAME}-unstable"

# check autodeploy
if [[ $CF_AUTODEPLOY == true ]]; then
    echo "Autodeploying"
    if [[ $TRAVIS_PULL_REQUEST == true ]]; then
        echo "Aborting, pull-request detected"
        exit 0;
    fi
    APP_ROUTE="${APP_NAME}-${TRAVIS_BRANCH}"
    if [[ $TRAVIS_BRANCH == 'master' ]]; then
        APP_ROUTE=$APP_NAME
        echo "Deploying prod to ${APP_NAME}"
    elif [[ $TRAVIS_BRANCH == 'develop' ]]; then
        echo "Deploying test to ${APP_NAME}-${TRAVIS_BRANCH}"
    else
        echo 'Not deploying due to wrong branch'
        exit 0;
    fi

    APP_NAME="${APP_NAME}-${TRAVIS_BRANCH}"
fi

echo "Deploying at route ${APP_ROUTE}"

CF_CMD=`which cf`

if [[ $CF_CMD == '' ]]; then
    curl -o /tmp/cf-linux-amd64.tgz http://go-cli.s3-website-us-east-1.amazonaws.com/releases/v6.10.0/cf-linux-amd64.tgz
    tar xvf /tmp/cf-linux-amd64.tgz -C /tmp
    echo "Using downloaded cf cli"
    CF_CMD="/tmp/cf"
fi

$CF_CMD api $CF_API
# call behind pipe to ensure that $CF_CMD login is not interactive
echo '' | $CF_CMD login -u $CF_USER -p $( $ECHO_CMD -n $CF_PASS) -o $CF_ORG -s $CF_SPACE
if [[ $? -ne 0 ]]; then
    echo "Auth failed"
    echo "Exited with non-zero exit code"
    exit 1;
fi

# push webinterface (does a green/blue deploy w/o rollback support)
$CF_CMD app "${APP_NAME}-blue"
if [[ $? -eq 0 ]]; then
    DEPLOY_TARGET="${APP_NAME}-green"
    OLD_TARGET="${APP_NAME}-blue"
fi
$CF_CMD app "${APP_NAME}-green"
if [[ $? -eq 0 ]]; then
    DEPLOY_TARGET="${APP_NAME}-blue"
    OLD_TARGET="${APP_NAME}-green"
fi

if [[ ! $DEPLOY_TARGET ]]; then
    echo "Initial Deploy, remember to set up the DB"
    DEPLOY_TARGET="${APP_NAME}-blue"
    OLD_TARGET="${APP_NAME}-green"
fi

echo "Deploying API to ${DEPLOY_TARGET}"
$CF_CMD push $DEPLOY_TARGET
if [[ $? -ne 0 ]]; then
    echo "Push to ${DEPLOY_TARGET}failed"
    echo "Exited with non-zero exit code"
    exit 1;
fi
echo "Deploy to ${DEPLOY_TARGET} was successful, remapping routes"
$CF_CMD map-route $DEPLOY_TARGET $CF_DOMAIN -n $APP_ROUTE
$CF_CMD unmap-route $OLD_TARGET $CF_DOMAIN -n $APP_ROUTE
echo "Reaping ${OLD_TARGET}"
$CF_CMD stop $OLD_TARGET
$CF_CMD delete $OLD_TARGET -f
echo "So Long, and Thanks for All the Fish"
