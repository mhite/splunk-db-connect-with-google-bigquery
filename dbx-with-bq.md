# Configuring DB Connect for use with Google BigQuery

While Splunk's DB Connect supports a wide range of out-of-the-box database connectors, Google's BigQuery is not one of them. With a little effort, however, we can build a custom JDBC add-on for DB Connect that allows Splunk to interface with your BigQuery data warehouse. This article details steps required for building such an add-on along with instructions for configuring the BigQuery connection within the DB Connect app.

## Prerequisites

* Splunk Enterprise or Splunk Enterprise Cloud environment
* curl, unzip, and jq CLI utilities
* gcloud SDK
* DB Connect installed with configured JRE
* Google Cloud project with a user possessing administrative privileges capable of managing service accounts and IAM
* Familiarity with the BigQuery billing model

## Caveat

Connecting DB Connect to a BigQuery data warehouse will [incur costs from Google Cloud](https://cloud.google.com/bigquery/docs/reference/odbc-jdbc-drivers#how_am_i_being_charged_when_querying_via_the_driver). Splunk is not responsible for queries that result in large or unexpected bills. Always test your queries in the BigQuery console to [preview the bytes scanned](https://cloud.google.com/bigquery/docs/best-practices-costs#estimate-query-costs) and determine if the associated cost of the scan is acceptable.

## JDBC Driver Add-on Primer

Installing JDBC drivers for supported DB Connect databases is a simple process. Each database has its drivers packaged into a dedicated add-on [as described in the documentation](https://docs.splunk.com/Documentation/DBX/3.16.0/DeployDBX/Installdatabasedrivers). Driver installation and upgrades can be managed independent of the DB Connect app.

But what happens when you want to use JDBC drivers for an unsupported database such as BigQuery? To install unsupported drivers, customers are advised to [follow the unsupported driver installation process](https://docs.splunk.com/Documentation/DBX/3.16.0/DeployDBX/Installdatabasedrivers#Install_unsupported_drivers_.28customer_managed_only.29). Part of this process involves adding files to the DB Connect app itself. This will work fine for environments that are fully under the control of the customer. However, for Splunk Cloud environments, this option is not available.

In order to work around this issue, a private add-on that looks and behaves like the ones Splunk supplies for its officially supported database drivers can be crafted. When DB Connect scans for Splunk supplied JDBC drivers, it traverses the app directory structure looking for add-ons that begin with "Splunk_JDBC_". By using this same naming convention and a special directory structure, users are able to craft their own custom add-ons containing unsupported JDBC drivers. Even better, these private add-ons can be installed in Splunk Cloud environments using the private app install process.

## Build the Add-on

The [shell script](./build.sh) found in this repository can be used to build a custom add-on containing the Google-supplied JDBC drivers. It will download the JDBC drivers, create configuration files, and generate an add-on suitable for installation in a Splunk Enterprise or Splunk Enterprise Cloud environment.

Once the script is finished executing, an add-on file with the name `Splunk_JDBC_BigQuery_100.tgz` will be present in the current working directory.

## Install the Add-On

In addition to installing the DB Connect App, the new custom JDBC add-on must also be installed. The installation process depends on whether the environment is self-hosted or Splunk Enterprise Cloud. Please see [Splunk Cloud documentation](https://docs.splunk.com/Documentation/SplunkCloud/9.1.2312/Admin/PrivateApps) for more information.

## Prepare Google Cloud environment

### Create Service Account

First, export several environment variables for use throughout the configuration instructions.

```bash
export SA_NAME=dbx-bq
export PROJECT_ID=<PROJECT_ID>
export KEY_FILE=dbx-bq-sa.json
export SA_EMAIL=${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com
```
 
Next, create a service account in a Google Cloud project.

```
gcloud iam service-accounts create ${SA_NAME} --project=${PROJECT_ID}
```

Export a JSON credential for this new service account.

```
gcloud iam service-accounts keys create ${KEY_FILE} --iam-account=${SA_EMAIL}
```

Grant this service account the `bigquery.user` role within the project scope. Optionally, to use the `dbxoutput` command provided by DB Connect, `bigquery.admin` can be granted instead. Note that the `bigquery.user` role is sufficient to use the `dbxquery` command.

```
gcloud projects add-iam-policy-binding ${PROJECT_ID} --member=serviceAccount:${SA_EMAIL} --role=roles/bigquery.user
```

In order to use the JSON credential within Splunk, we will need to flatten the JSON into a single line. The easiest way to do this is using the "jq" utility:

```
jq -c . ${KEY_FILE}
```

This should output the JSON on a single line similar to the redacted output below.

```
{"type":"service_account","project_id":"<REDACTED>,"private_key_id":"e580bb185173189d15a653408a24957ffb8d2872","private_key":"-----BEGIN PRIVATE KEY-----\n<REDACTED>\n-----END PRIVATE KEY-----\n","client_email":"dev-dbx-bq-sa@<REDACTED>.iam.gserviceaccount.com","client_id":"109787105253850867414","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_x509_cert_url":"https://www.googleapis.com/robot/v1/metadata/x509/dev-dbx-bq-sa%40<REDACTED>.iam.gserviceaccount.com","universe_domain":"googleapis.com"}
```

Copy and paste this flattened JSON into a text file so we can reference it later in our DB Connect configuration. 

### Configure DB Connect

To prepare DB Connect for a BigQuery connection, you must first define a placeholder identity and a new connection.

### Create an identity

Within the Splunk DB Connect App, navigate to Configuration / Databases / Identities. Click the "New Identity" button and select "Basic Identity."

![DB Connect Identity](./images/dbx-identity.png)

For the Identity Name, Username, and Password fields, enter "bq". Click the "Save" button.

### Create a connection

Next, navigate to Configuration / Databases / Connections. Click the "New Connection" button.

Enter "bq" as the connection name. Select "bq" as the Identity and "BigQuery" as the Connection Type. For Timezone, select "Etc/UTC".

Next, place a check mark next to the "Edit JDBC URL" option. This will allow you to edit the JDBC connection URL and inject a service account credential.

To craft the custom JDBC URL, use the following format:

```
jdbc:bigquery://https://www.googleapis.com/bigquery/v2:443;EnableSession=1;ProjectId=<YOUR-PROJECT>;OAuthType=0;OAuthServiceAcctEmail=<YOUR-SERVICE-ACCOUNT-EMAIL>;OAuthPvtKey=<JSON-SERVICE-ACCOUNT-KEY>;
```

You will need to substitute the project ID for `<YOUR-PROJECT>`. Similarly, `<YOUR-SERVICE-ACCOUNT-EMAIL>` must be substituted for email of the service account created in the account creation steps from the previous section. The `<JSON-SERVICE-ACCOUNT-KEY>` must be replaced with the single-line version of the service account key you previously reformatted with the "jq" command. Ensure the JDBC URL ends with a semicolon.

For example:

```
jdbc:bigquery://https://www.googleapis.com/bigquery/v2:443;EnableSession=1;ProjectId=my-project-151018;OAuthType=0;OAuthServiceAcctEmail=dev-dbx-bq-sa@my-project-151018.iam.gserviceaccount.com;OAuthPvtKey={"type":"service_account","project_id":"my-project-151018","private_key_id":"8715a33233d1d7f3a1f8c6138eb780b474c67422","private_key":"-----BEGIN PRIVATE KEY-----\n<REDACTED>-----END PRIVATE KEY-----\n","client_email":"dev-dbx-bq-sa@gsa-project-151018.iam.gserviceaccount.com","client_id":"109787105253850867414","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_x509_cert_url":"https://www.googleapis.com/robot/v1/metadata/x509/dev-dbx-bq-sa%40my-project-151018.iam.gserviceaccount.com","universe_domain":"googleapis.com"};
```

![DB Connect Connection](./images/dbx-connection.png)

Ignore the Advanced settings and click the "Save" button to finish.

## Test

Now that the BigQuery connection has been defined in DB Connect, we're ready to issue our first query. We'll use an example public data set. _Please note that performing this query will result in BigQuery charges. As mentioned in the caveats section, it is your responsibility to perform the dry-run in the BigQuery console to estimate costs_.

Navigate to the "Search" app and enter the following the Splunk search box:

```
| dbxquery query="SELECT * FROM `bigquery-public-data.noaa_historic_severe_storms.storms_2023`" connection="bq"
```

![DB Connect Query](./images/dbx-query.png)

This should return ~ 87,564 rows.

## Limitations

* The private key for the service account is visible in the JDBC URL and is not stored encrypted
* Custom add-ons containing jar files must go through manual vetting in a Splunk Cloud environment
* Customers should review GoogleSQL [DML limitations](https://cloud.google.com/bigquery/docs/data-manipulation-language#limitations)

## Acknowledgement

This article would not be possible without the essential technical contributions of Carlos Alberto Nuñez, Maurice Johnson, Mike Sakahara, and Nic Stone.
