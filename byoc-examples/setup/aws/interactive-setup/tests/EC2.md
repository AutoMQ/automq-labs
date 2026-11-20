---
last_updated: 2026-11-20
---

# EC2 setup regression cases

Run the EC2 cases from the `interactive-setup` directory. The offline suite
exercises resource discovery, menu choices, preparation commands, IAM policy
scopes, and CMP request fields. It uses an AWS fixture and makes no cloud
calls. The request matrix covers 88 combinations of bucket ownership, DNS
mode, Broker security group ownership, and the 11 valid Kafka transport and
authentication selections.

```bash
python3 -m unittest discover -s tests -p 'test_ec2_*.py' -v
```

To run the real AWS preparation scripts in a temporary VPC, use the existing
opt-in preparation test. It creates and cleans up its own test resources.
Keep the output directory to inspect the command log and cleanup results.

```bash
python3 tests/live_aws_precreate.py --run --region us-east-1 \
  --output "$HOME/automq-precreate-$(date +%Y%m%d-%H%M%S)"
```

## Cloud cases

Start each case with a new cluster name and a new private output directory.
Use a test VPC with DNS support and DNS hostnames enabled, private subnets,
and routes for Home, the Console image registry, and the required AWS
services. Use an AWS CLI identity in the same account as the test environment.
Use a Home environment with an available UsageBased subscription or trial.
For a new Console, have a private access route and an EC2 key pair ready.

| Case | Select in the guide | Evidence to check |
| --- | --- | --- |
| Reuse customer resources | Existing Console, VPC, compute subnets, S3 Gateway Endpoint, an unused user-owned data bucket, associated Private Hosted Zone, Broker security group, and EC2 IAM roles. Select EBS WAL and SASL over TLS. Supply a server certificate and key for the existing zone. | Skip all resource preparation commands. Verify the signed request carries the existing bucket, zone, subnets, group, and Broker Role. Verify IAM grants target the selected roles. Existing IAM attachments remain attached. |
| Prepare missing resources | New EC2 Console in an existing VPC. In the resource menus, use **Show preparation command** for a missing subnet, Private Hosted Zone, user-managed bucket, security groups, and EC2 roles and profiles. Select S3 WAL and SASL plaintext. | Execute the displayed scripts, refresh, and select the resulting IDs. Review how the new subnet reaches dependencies. If the S3 Gateway Endpoint exists, the generated command adds only missing route tables and preserves its policy. Check the Console launch receipt and its instance profile. |
| Reuse networking with CMP-managed resources | Existing Console and roles, VPC, subnets and S3 Gateway Endpoint. Select CMP-managed bucket and Broker security group, Private DNS, and a VPC client source. | The request omits customer bucket and group IDs. CMP reports managed resources. Listener ingress uses the selected client CIDR. The Console policy grants the required create operations. |
| Combine user-managed resources with EFS and Public DNS | Three AZs with one Broker each. Reuse the Console and network. Select a user-managed bucket and Broker security group, EFS WAL and a CMP-managed EFS security group. Select Public DNS and both SASL over TLS and mTLS. Supply the client CA. | The request references the selected bucket and Broker group. Home supplies the Public Zone and server certificate. EFS has an available mount target in each selected AZ. Verify Kafka in both directions. Run once with resources prepared in the wizard and again with equivalent resources prepared before opening it. |
| Reuse an EFS security group | Repeat the EFS case with a pre-existing NFS security group and pre-existing EFS mount-target subnets. | The signed request and CMP's file system details use the selected group. CMP creates the file system and mount targets. |

The new-Console and mixed EFS cases have cloud results from earlier runs.
The mixed EFS run reused a Console, VPC, route table and S3 Gateway Endpoint.
It used a bucket, Broker security group and Broker Role created for that run.
The scenario that selects only pre-existing customer dependencies has offline
coverage. An existing EFS or FSx file system ID is outside the CMP create
request. The guide supports reusing the surrounding subnets and security groups.

## Execute and verify a case

1. Run `python3 setup.py --output "$BUNDLE"` with a new absolute output path.
   For resources that already exist, select their IDs directly. For missing
   resources, execute the displayed `prepare-*.sh` command in another terminal
   and enter `r` in the guide when the resource is visible in AWS.
2. For an existing EC2 Console, use its attached instance profile to identify
   the IAM role. Run the following commands with the test Console instance ID
   and AWS Region. The first command returns the ARN. Pass its final path
   component as `PROFILE_NAME` to the second command, then select the returned
   role in the wizard.

   ```bash
   aws ec2 describe-instances --region "$AWS_REGION" --instance-ids "$CONSOLE_INSTANCE_ID" \
     --query 'Reservations[].Instances[].IamInstanceProfile.Arn' --output text
   aws iam get-instance-profile --instance-profile-name "$PROFILE_NAME" \
     --query 'InstanceProfile.Roles[].RoleName' --output text
   ```

3. When the guide prepares a new subnet, associate it with the intended
   private route table if the VPC's main route table lacks the required routes.
   Review `s3-endpoint-policy-review.json` for access to the Ops and data
   buckets. Confirm the Broker security group admits the selected client
   CIDRs and the Console can reach the Broker management ports. With customer
   storage encryption keys, verify the key policy and IAM grants separately.

   ```bash
   aws ec2 associate-route-table --region "$AWS_REGION" \
     --subnet-id "$NEW_SUBNET_ID" --route-table-id "$PRIVATE_ROUTE_TABLE_ID"
   ```

4. Review the bundle and grant the generated policies. Use the account and
   Region selected in the wizard. For a new Console, start the instance and
   follow the generated host installation instructions before signing.

   ```bash
   bash "$BUNDLE/authorize-cluster-role.sh"
   bash "$BUNDLE/authorize-console-role.sh"
   # New EC2 Console only
   bash "$BUNDLE/prepare-console-ec2.sh"
   ```

5. Wait for IAM propagation and check Console initialization, Home `ACTIVE`
   and the subscription or trial. For an existing Console, fill in the private
   `cmp-credentials.json` with its service-account credentials. Set
   `CONSOLE_URL` to the origin reachable from the submission host. Run the
   generated command, then save the signed directory and response with the
   original bundle.

   ```bash
   bash "$BUNDLE/generate-curl.sh" "$CONSOLE_URL" signed-create
   bash "$BUNDLE/signed-create/create-cluster.sh"
   ```

6. After the cluster reaches `Running` and EC2 checks pass, compare the
   receipt with live CMP and AWS state. The verifier reads the selected
   dependencies, Broker placement and profiles, endpoints, and EFS mount
   targets. It prints JSON you can save as evidence. Use `--console-url` if
   your private Console address or tunnel port changed.

   ```bash
   python3 tests/verify_live_ec2.py --bundle "$BUNDLE"
   ```

## Verify both Kafka TLS listeners

Run the checks from a host that reaches the private Broker addresses. Wait
until the host's default resolver returns all Broker addresses. Use the
bootstrap hostnames from the verifier so the Kafka clients can check
certificate names.

Create a one-partition test Topic, a temporary SASL user, and a client
certificate signed by the configured client CA. Grant both Kafka principals
produce and consume permissions scoped to the test Topic and read access to
its test consumer group. Use the client certificate's common name for the
mTLS principal. Keep client keys and the SASL password in mode-0600 files.

Check all Broker hostnames on both TLS ports. For a Private Zone, pass the
server CA with `-CAfile`. For the Home-issued certificate, use the client's
system trust. Supply `-cert` and `-key` for port 9122. The third command
keeps reading after the handshake so OpenSSL can report the server's
certificate-required TLS alert.

```bash
openssl s_client -connect "$BROKER_HOST:9112" -servername "$BROKER_HOST" \
  -verify_hostname "$BROKER_HOST" -verify_return_error -brief </dev/null
openssl s_client -connect "$BROKER_HOST:9122" -servername "$BROKER_HOST" \
  -verify_hostname "$BROKER_HOST" -verify_return_error -brief \
  -cert "$CLIENT_CERT" -key "$CLIENT_KEY" </dev/null
timeout 10 openssl s_client -connect "$BROKER_HOST:9122" -servername "$BROKER_HOST" \
  -verify_hostname "$BROKER_HOST" -verify_return_error -brief -ign_eof </dev/null
```

Use two private `kcat` configuration files. The SASL file needs
`security.protocol=SASL_SSL`, a supported `sasl.mechanism`, the temporary
`sasl.username` and `sasl.password`, and the port 9112 `bootstrap.servers`.
The mTLS file needs `security.protocol=SSL`, `ssl.certificate.location`,
`ssl.key.location`, and the port 9122 `bootstrap.servers`. Set
`ssl.ca.location` when a private CA issued the server certificate. Keep
hostname validation enabled on both clients. Use a new Topic so the first
two messages occupy offsets 0 and 1. [kcat configuration](https://github.com/edenhill/kcat#configuration)

```bash
printf '%s\n' sasl-to-mtls | kcat -F "$SASL_CONFIG" -P -t "$TEST_TOPIC" -p 0
timeout 20 kcat -F "$MTLS_CONFIG" -C -t "$TEST_TOPIC" -p 0 -o 0 -c 1 -q
printf '%s\n' mtls-to-sasl | kcat -F "$MTLS_CONFIG" -P -t "$TEST_TOPIC" -p 0
timeout 20 kcat -F "$SASL_CONFIG" -C -t "$TEST_TOPIC" -p 0 -o 1 -c 1 -q
```

Check that each consumer prints the value sent from the other listener.
Remove the Topic, temporary ACLs and SASL user after verification.

## Clean up and rerun

Preview cluster deletion from the original bundle. Apply the same command
when you are ready to remove the cluster.

```bash
bash "$BUNDLE/cleanup.sh" --cluster-only
bash "$BUNDLE/cleanup.sh" --apply --cluster-only
```

The script retains the Console, user-managed dependencies, and IAM policies.
Before repeating a case against the same roles, review their attached policy
quota. When a test policy is obsolete, detach only the policy named for that
completed run after confirming that the Console and remaining clusters do
not use it. Repeat with a new cluster name and an unused test bucket.
