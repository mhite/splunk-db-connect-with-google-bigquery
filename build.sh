#!/bin/sh

set -euo pipefail

# Define the URL of the zip file
DRIVER_URL="https://storage.googleapis.com/simba-bq-release/jdbc/SimbaJDBCDriverforGoogleBigQuery42_1.5.2.1005.zip"

# Define the destination directory for the unzipped files
DEST_DIR="./dist/Splunk_JDBC_BigQuery"
TMP_DIR="./tmp"

# Check for required tools
if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required but not found."
    exit 1
fi

if ! command -v unzip >/dev/null 2>&1; then
    echo "unzip is required but not found."
    exit 1
fi

prepare_driver() {
    mkdir -p ${DEST_DIR}/lib/dbxdrivers/GoogleBigQueryJDBC42-libs
    mkdir -p ${TMP_DIR}

    echo "Downloading the zip file..."
    curl -L -o ${TMP_DIR}/SimbaJDBCDriver.zip "$DRIVER_URL"

    echo "Unzipping the file..."
    unzip ${TMP_DIR}/SimbaJDBCDriver.zip -d "${TMP_DIR}"

    echo "Moving GoogleBigQueryJDBC42.jar to the drivers directory..."
    mv "${TMP_DIR}/GoogleBigQueryJDBC42.jar" "${DEST_DIR}/lib/dbxdrivers/GoogleBigQueryJDBC42.jar"

    echo "Moving other jar files to the drivers-lib directory..."
    mv "${TMP_DIR}/"*.jar "${DEST_DIR}/lib/dbxdrivers/GoogleBigQueryJDBC42-libs/"
}

make_config() {
    mkdir -p ${DEST_DIR}/default

    echo "Creating configuration files..."
    cat > ${DEST_DIR}/default/app.conf << EOF
# Splunk app configuration file

[install]
is_configured = false
state_change_requires_restart = false
build = 1.0.0
python.version = python3

[ui]
is_visible = false
label = Splunk_JDBC_BigQuery

[launcher]
author = MDS
description = JDBC Driver and config for BigQuery
version = 1.0.0

[package]
id = Splunk_JDBC_BigQuery
check_for_updates = false
show_upgrade_notification = false

[id]
name = Splunk_JDBC_BigQuery
version = 1.0.0

[triggers]
reload.db_connection_types = simple

[shclustering]
deployer_lookups_push_mode = preserve_lookups
deployer_push_mode = merge_to_default
EOF

    cat > ${DEST_DIR}/default/db_connection_types.conf << EOF
[bigquery]
displayName = BigQuery
serviceClass = com.splunk.dbx2.DefaultDBX2JDBC
jdbcUrlFormat = jdbc:bigquery://https://www.googleapis.com/bigquery/v2:443;EnableSession=1;ProjectId=<projectid>;OAuthType=3;
jdbcDriverClass = com.simba.googlebigquery.jdbc42.Driver
ui_default_catalog = \$database\$
EOF
}

cleanup() {
    echo "Cleaning up temporary files..."
    rm -rf ${TMP_DIR}
}

trap cleanup EXIT ERR

prepare_driver
make_config

# Compress the directory into a tarball
echo "Compressing the directory..."
COPYFILE_DISABLE=1 tar -czf Splunk_JDBC_BigQuery_100.tgz -C ./dist Splunk_JDBC_BigQuery
