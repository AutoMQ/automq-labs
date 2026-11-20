"""Generate, but never execute, EC2 Console installation commands."""
from pathlib import Path
import json
from core import TEMPLATES, aws_command, tags, write_private


def generate_console(directory, state):
    directory = Path(directory)
    config = state['console_config']
    region = state['home']['region']
    name = f'automq-setup-{state["name"]}-console'
    groups = [config['security_group']['GroupId']]
    # All identifiers are actual selected values. No host shell expansion is used to serialize JSON.
    devices = [
        {'DeviceName': config['ami']['RootDeviceName'], 'Ebs': {'VolumeSize': 20, 'VolumeType': 'gp3', 'Encrypted': True, 'DeleteOnTermination': True}},
        {'DeviceName': '/dev/sdf', 'Ebs': {'VolumeSize': 20, 'VolumeType': 'gp3', 'Encrypted': True, 'DeleteOnTermination': False}},
    ]
    spec = []
    for resource in ['instance', 'volume']:
        purpose = 'console' if resource == 'instance' else 'console-volume'
        spec.append({'ResourceType': resource, 'Tags': [{'Key': 'Name', 'Value': name}] + tags(state['name'], purpose)})
    write_private(directory / 'console-devices.json', devices)
    write_private(directory / 'console-tags.json', spec)
    cmd = aws_command(region, 'ec2', 'run-instances', '--image-id', config['ami']['ImageId'], '--instance-type', 't3.large',
        '--subnet-id', state['subnet']['SubnetId'], '--security-group-ids', *groups,
        '--iam-instance-profile', 'Arn=' + state['console_role_profile']['Arn'],
        '--key-name', config['key_name'], '--no-associate-public-ip-address',
        '--block-device-mappings', 'file://console-devices.json', '--tag-specifications', 'file://console-tags.json',
        '--metadata-options', 'HttpTokens=required,HttpEndpoint=enabled', '--client-token', state['name'] + '-console',
        '--count', '1', '--query', 'Instances[0].InstanceId', '--output', 'text')
    wait = aws_command(region, 'ec2', 'wait', 'instance-running') + ' --instance-ids "$SETUP_INSTANCE_ID"'
    launch_result = ("Reservations[0].Instances[0].{InstanceId:InstanceId,PrivateIp:PrivateIpAddress,"
                     "DataVolumeId:BlockDeviceMappings[?DeviceName=='/dev/sdf'].Ebs.VolumeId | [0]}")
    query = aws_command(region, 'ec2', 'describe-instances', '--query', launch_result, '--output', 'json') + ' --instance-ids "$SETUP_INSTANCE_ID"'
    write_private(directory / 'prepare-console-ec2.sh', '#!/usr/bin/env bash\nset -euo pipefail\ncd -- "$(dirname -- "$0")"\nSETUP_INSTANCE_ID=$(' + cmd + ')\n' + wait + '\n' + query + '\n')
    disk = (TEMPLATES / 'console-data-disk.sh').read_text()
    check_mount = (TEMPLATES / 'automq-console-check-mount').read_text()
    unit = (TEMPLATES / 'automq-console.service').read_text()
    unit = unit.replace('<home-console-image>', state['home']['image'])
    write_private(directory / 'automq-console-check-mount', check_mount)
    write_private(directory / 'automq-console.service', unit)
    write_private(directory / 'runtime.env', '\n'.join([
        'CONFIG=' + state['home']['config'], 'CLOUD_PROVIDER=aws', 'CONSOLE_INITIAL_USER=admin',
        'CONSOLE_INITIAL_PASSWORD=' + config['password'],
        'CONSOLE_INITIAL_ACCESS_KEY=' + state['api_credentials']['accessKey'],
        'CONSOLE_INITIAL_SECRET_KEY=' + state['api_credentials']['secretKey']]) + '\n')
    preamble = '''#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
# Run on the new AL2023 Console EC2, after securely copying this bundle there.
[ "$#" -eq 1 ] || { echo 'Usage: bash install-console.sh vol-DATA_VOLUME_ID'; exit 1; }
[[ "$1" =~ ^vol-[a-f0-9]+$ ]] || exit 1
[ ! -e /etc/automq-console/runtime.env ] || { echo 'Console configuration already exists; compare before reinstalling.'; exit 1; }
sudo dnf install -y docker xfsprogs
sudo systemctl enable --now docker
if sudo docker container inspect automq-console >/dev/null 2>&1; then
  echo 'An automq-console container already exists; stop and inspect it.'
  exit 1
fi
'''
    post = '''
sudo install -d -m 0700 /etc/automq-console
sudo install -d -m 0755 /usr/local/libexec
printf '%s\\n' "$SETUP_UUID" > console-data.uuid
chmod 0600 console-data.uuid runtime.env
sudo install -m 0600 console-data.uuid /etc/automq-console/data.uuid
sudo install -m 0600 runtime.env /etc/automq-console/runtime.env
sudo install -m 0755 automq-console-check-mount /usr/local/libexec/automq-console-check-mount
sudo install -m 0644 automq-console.service /etc/systemd/system/automq-console.service
sudo systemctl daemon-reload
sudo systemctl enable --now automq-console
sudo /usr/local/libexec/automq-console-check-mount
sudo systemctl status automq-console --no-pager
'''
    write_private(directory / 'install-console.sh', preamble + disk + '\n' + post)
    write_private(directory / 'CONSOLE-INSTALL.txt', f'''Execute authorization scripts first. Verify IAM propagation before launching EC2.
Run bash prepare-console-ec2.sh locally. Record InstanceId, PrivateIp and DataVolumeId from its JSON output.
Use your existing private-network SSH route and selected key {config['key_name']} to reach the new EC2 private IP.
Copy install-console.sh, runtime.env, automq-console-check-mount, automq-console.service to a private directory on that EC2.
Run bash install-console.sh <DataVolumeId> on the new EC2.
The guide does not execute SSH or cloud writes. Keep runtime.env private.
Access TCP 8080 through the reviewed private network route or SSH local port forwarding.
Confirm Console health and persistence. Wait for Home ACTIVE, then verify the environment has an available UsageBased subscription or trial before running create-cluster.sh. These are separate prerequisites; metadata and subscription refresh are asynchronous.
Run generate-curl.sh locally with the Console origin reachable from the execution machine and a new output directory. Transfer the generated signed bundle to that machine; run its create-cluster.sh there. Do not transfer cmp-credentials.json.
''')
