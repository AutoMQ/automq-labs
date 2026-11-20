---
last_updated: 2026-11-20
---

# Interactive AutoMQ setup on AWS

Use an existing AWS VPC to configure an AutoMQ cluster on EC2 or EKS. The guide
discovers dependencies and generates IAM policies, an OpenAPI create request
and, when selected, Console installation commands.

## Run the guide

Run these commands from the AutoMQ Labs repository root. The guide requires
Python 3.9+, an authenticated AWS CLI and OpenSSL. Set `AWS_PROFILE` if you
want to use a named profile.

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r byoc-examples/setup/aws/interactive-setup/requirements.txt
python byoc-examples/setup/aws/interactive-setup/setup.py \
  --output "$HOME/automq-setup-$(date +%Y%m%d-%H%M%S)"
```

Use a new private output directory outside the repository. At the hidden
prompt, paste the complete Docker command from AutoMQ Home. The guide reads the
AWS Region, Ops Bucket and Console image from it. It uses read-only AWS CLI
queries. If you select Public DNS and confirm, the guide calls Home to prepare
the environment's DNS resources.

Choose an existing Console or select **Install a new Console**. Select the
cluster topology and dependencies, then review the generated IAM policies and
the authorization commands. Review `cluster-request.json` locally before
signing it.

For broker configuration overrides, add `--instance-configs /path/to/configs.json`.
Use a JSON object with string values, such as `{"num.network.threads":"8"}`. The
guide writes the entries to `features.instanceConfigs` in the create request.
CMP validates them for the target release. The guide hides values in the
terminal preview, and the private request file contains the actual values.
Kubernetes values and Topic config changes require their own product interfaces.

## Install a new Console on EC2

Selecting EC2 for a new Console generates `prepare-console-ec2.sh`. Run the
authorization commands for the selected Console Role, then launch the EC2
instance from the output directory.

```bash
bash prepare-console-ec2.sh
```

The AWS CLI command uses the selected private subnet, security group, SSH key
and instance profile. It records `InstanceId`, `PrivateIp` and `DataVolumeId` in
`console-launch.json`.
Use your private network route to copy the files listed in
`CONSOLE-INSTALL.txt` to the host and run `bash install-console.sh <DataVolumeId>`.
The installer mounts the encrypted EBS data volume, then starts the Home image
with Docker host networking and binds the data directory to `/root`. systemd
starts the container after the data volume is mounted. The private
`runtime.env` supplies the Home CONFIG, initial admin password and initial CMP
service-account credentials.

For a new EKS Console, follow the generated `CONSOLE-INSTALL.md`. The bundle
uses a local copy of the published AutoMQ BYOC Console Chart 8.4.13, with
initial credentials read from a Kubernetes Secret. Helm and kubectl run where
the EKS API is reachable.

## Create the cluster through CMP OpenAPI

For an existing Console, populate the private `cmp-credentials.json` with its
service-account access key and secret key. The guide generates the initial
service-account credentials for a new Console. Verify that Console has
initialized, Home shows the environment as `ACTIVE`, and its UsageBased
subscription or trial is available.

From the output directory, sign the request using the Console origin as seen
from the machine that will run curl.

```bash
bash generate-curl.sh http://cmp.internal:8080 signed-create
```

The generator prints the curl command. Copy the entire `signed-create`
directory to the execution machine if needed and run the command there.
If curl uses a proxy, include the private Console hostname in `no_proxy`
when it must be reached directly.

```bash
cd signed-create
umask 077
curl --disable --config request.curl --fail-with-body --silent --show-error \
  --connect-timeout 10 --max-time 120 --output create-response.json
```

The command submits `POST /api/v1/instances`. `bash create-cluster.sh` sends
the same request and reports common failure cases. Keep the signed bundle
private. Generate it shortly before submission and sign again if the payload
or Console origin changes. `create-response.json` contains the API response.
Check the cluster's status in Console before retrying a request with an unknown
result.

## Clean up a test deployment

Keep the original output directory and the signed create directory with its
`request.json`, `create-target.json` and successful `create-response.json`. If
you ran the create request elsewhere, copy those files back into the signed
create directory in the original output bundle. Keep `console-launch.json` for
a new EC2 Console and `console-eks.uid` for a new EKS Console.

From the original output directory, run:

```bash
bash cleanup.sh          # Preview
bash cleanup.sh --apply  # Execute
```

CMP deletes the recorded cluster and handles its managed resources. The script
waits until CMP no longer finds the cluster before removing a new Console. For
EC2, it terminates the recorded instance and deletes its dedicated EBS data
volume. For EKS, it uninstalls the recorded Helm release. The Retain policy
preserves the EKS persistent volume. Separately prepared dependencies such as
IAM roles, DNS zones, network resources, and S3 buckets stay in place.

The script keeps an existing Console. Use `--cluster-only` if you want to
keep a new Console or it manages other clusters. If the bundle contains
multiple create results, use `--receipt /path/to/signed-create` to select the
successful one. Use `--console-url` if the private Console address or tunnel
port changes. The service account needs permission to read and delete the
cluster and, when removing Console, to list its other clusters. EC2 cleanup
uses the AWS CLI identity for the recorded account. EKS cleanup uses Helm
and kubectl with the recorded context.

If the command stops waiting for a deletion, rerun it with `--apply` to
resume. Keep the output bundle until cleanup completes.

## Compatibility and tests

The guide maps Console `8.4.13-aws` to AutoMQ Kafka `5.5.9`, including the AMI
lookup for EC2 clusters. Other Console images use the inherited Kafka `5.5.6`
development baseline. Verify that the Console offers that Kafka version before
using its request. EKS runtime and IAM behavior still require validation in the
target environment.

Run the offline suite from the repository root with Helm, OpenSSL and curl on
PATH.

```bash
python -m unittest discover -s byoc-examples/setup/aws/interactive-setup/tests -v
```
