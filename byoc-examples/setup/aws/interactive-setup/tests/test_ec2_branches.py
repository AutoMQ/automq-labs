from itertools import product
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import MagicMock, patch

from test_setup import fixture
from certificates import verify_server_chain
from core import AWS, SetupError, policies, request_body
from flows import AWSWizard
from home import prepare_public_dns
from model import listeners
from resources import sg_command, sg_rules, validate_sg
from setup import UI


class EC2CreateBranches(unittest.TestCase):
    def test_bucket_dns_and_security_matrix(self):
        security_modes = [
            (['plaintext'], ['anonymous'], ['PLAINTEXT']),
            (['plaintext'], ['sasl'], ['BROKER_SASL']),
            (['plaintext'], ['sasl', 'anonymous'], ['BROKER_SASL', 'PLAINTEXT']),
            (['tls'], ['sasl'], ['BROKER_SASL_SSL']),
            (['tls'], ['mtls'], ['BROKER_MTLS']),
            (['tls'], ['sasl', 'mtls'], ['BROKER_SASL_SSL', 'BROKER_MTLS']),
            (['plaintext', 'tls'], ['sasl'], ['BROKER_SASL', 'BROKER_SASL_SSL']),
            (['plaintext', 'tls'], ['sasl', 'anonymous'], ['BROKER_SASL', 'PLAINTEXT', 'BROKER_SASL_SSL']),
            (['plaintext', 'tls'], ['anonymous', 'mtls'], ['PLAINTEXT', 'BROKER_MTLS']),
            (['plaintext', 'tls'], ['sasl', 'mtls'],
             ['BROKER_SASL', 'BROKER_SASL_SSL', 'BROKER_MTLS']),
            (['plaintext', 'tls'], ['sasl', 'anonymous', 'mtls'],
             ['BROKER_SASL', 'PLAINTEXT', 'BROKER_SASL_SSL', 'BROKER_MTLS']),
        ]
        for bucket, dns, existing_sg, (transport, auth, names) in product(
                (None, 'user-data'), ('private', 'public'), (False, True), security_modes):
            with self.subTest(bucket=bucket, dns=dns, existing_sg=existing_sg, transport=transport, auth=auth):
                state = fixture()
                state.update(data_bucket=bucket, dns_mode=dns, transport=transport, auth=auth,
                             client_cidrs=['10.0.0.0/16', '172.16.1.0/24'])
                state['cluster_security_groups'] = [{'GroupId': 'sg-test'}] if existing_sg else []
                role = 'arn:aws:iam::999999999999:role/home-dns'
                state['public_dns'] = {'crossAccountRole': role}
                state['tls_material'] = {'certificateChain': 'test-leaf', 'privateKey': 'test-key',
                                         'certificateAuthority': 'test-ca'}
                body = request_body(state)
                spec, features = body['spec'], body['features']
                self.assertEqual(spec['dataBuckets'], [{'bucketName': bucket}] if bucket else [])
                self.assertEqual(spec.get('dnsZoneType'), 'PUBLIC' if dns == 'public' else None)
                self.assertEqual(spec.get('dnsZone'), 'ZTEST' if dns == 'private' else None)
                security = features['security']
                self.assertEqual('certificateChain' in security, dns == 'private' and 'tls' in transport)
                self.assertEqual('privateKey' in security, dns == 'private' and 'tls' in transport)
                self.assertEqual('certificateAuthority' in security,
                                 'tls' in transport and (dns == 'private' or 'mtls' in auth))
                if existing_sg:
                    self.assertEqual(spec['securityGroups'], ['sg-test'])
                    self.assertNotIn('inboundRules', features)
                else:
                    self.assertNotIn('securityGroups', spec)
                    self.assertEqual(features['inboundRules'], [
                        {'listenerName': name, 'cidrs': state['client_cidrs']} for name in names
                    ])
                cluster, console = policies(state)
                cluster_sids = {entry['Sid']: entry for entry in cluster['Statement']}
                console_sids = {entry['Sid']: entry for entry in console['Statement']}
                console_actions = {action for entry in console['Statement'] for action in entry['Action']}
                self.assertEqual('ec2:CreateSecurityGroup' in console_actions, not existing_sg)
                if bucket:
                    self.assertEqual(console_sids['ReadDataBucket']['Resource'], ['arn:aws:s3:::user-data'])
                    self.assertNotIn('CreateDataBucket', console_sids)
                else:
                    self.assertIn('CreateDataBucket', console_sids)
                if dns == 'public':
                    self.assertEqual(console_sids['AssumeHomeDNSRole']['Resource'], [role])
                    self.assertNotIn('ManagePrivateDNS', console_sids)
                    self.assertEqual(cluster_sids['TlsAssumeRole']['Resource'], [role])
                    if 'tls' in transport:
                        self.assertEqual(cluster_sids['TlsDns']['Resource'], ['arn:aws:route53:::hostedzone/ZTEST'])
                        self.assertCountEqual(cluster_sids['TlsDns']['Action'], [
                            'route53:GetHostedZone', 'route53:ListResourceRecordSets', 'route53:ChangeResourceRecordSets'
                        ])
                    else:
                        self.assertNotIn('TlsDns', cluster_sids)
                else:
                    self.assertEqual(console_sids['ManagePrivateDNS']['Resource'], ['arn:aws:route53:::hostedzone/ZTEST'])
                    self.assertNotIn('AssumeHomeDNSRole', console_sids)
                    if 'tls' in transport:
                        self.assertEqual(cluster_sids['TlsAssumeRole']['Action'], ['sts:AssumeRole'])
                        self.assertEqual(cluster_sids['TlsAssumeRole']['Resource'], [state['cluster_role']['Arn']])
                    else:
                        self.assertNotIn('TlsAssumeRole', cluster_sids)

    def test_incomplete_tls_inputs_are_rejected_before_serializing(self):
        state = dict(fixture(), transport=['tls'], auth=['sasl'], dns_mode='private')
        with self.assertRaisesRegex(SetupError, 'server certificate'):
            request_body(state)
        state.update(auth=['mtls'], dns_mode='public')
        with self.assertRaisesRegex(SetupError, 'CA trust bundle'):
            request_body(state)

    def test_existing_sg_uses_selected_cidrs_and_does_not_override_them(self):
        state = dict(fixture(), client_cidrs=['10.0.0.0/16'], auth=['sasl'],
                     transport=['plaintext', 'tls'], dns_mode='private')
        state['vpc']['CidrBlock'] = '10.0.0.0/16'
        state['listeners'] = listeners(state['transport'], state['auth'])
        state['tls_material'] = {'certificateChain': 'test-leaf', 'privateKey': 'test-key'}
        state['cluster_security_groups'] = [{'GroupId': 'sg-test'}]
        rules = sg_rules(state)
        self.assertEqual(sum(port == 9102 for port, _, _ in rules), 1)
        self.assertTrue(all(source == '10.0.0.0/16' for _, source, _ in rules))
        self.assertEqual(request_body(state)['spec']['securityGroups'], ['sg-test'])
        self.assertNotIn('inboundRules', request_body(state)['features'])
        wrong = {'VpcId': state['vpc']['VpcId'], 'IpPermissions': [
            {'IpProtocol': '-1', 'IpRanges': [{'CidrIp': '192.0.2.0/24'}]}]}
        with self.assertRaisesRegex(SetupError, 'Missing inbound rules'):
            validate_sg(wrong, state['vpc']['VpcId'], rules)
        with tempfile.TemporaryDirectory() as temp:
            command = sg_command(Path(temp), state, 'cluster-sg', rules).read_text()
        self.assertEqual(command.count('--port 9102 --cidr 10.0.0.0/16'), 1)
        self.assertNotIn('0.0.0.0/0', command)

    def test_public_dns_preparation_skips_certificate_issuance(self):
        reply = {'hostedZoneId': '/hostedzone/ZTEST', 'crossAccountRole': 'arn:aws:iam::999999999999:role/home-dns',
                 'tlsCertificate': {'certificateChain': 'unused', 'privateKey': 'unused'}}
        opener = MagicMock()
        opener.open.return_value.__enter__.return_value.read.return_value = json.dumps(reply).encode()
        with patch('home.urllib.request.build_opener', return_value=opener):
            prepared = prepare_public_dns({'clientId': 'test-client', 'clientSecret': 'test-secret'})
        self.assertEqual(json.loads(opener.open.call_args.args[0].data), {'enableTls': False})
        self.assertEqual(prepared, {'hostedZoneId': 'ZTEST', 'crossAccountRole': reply['crossAccountRole']})

    def test_buckets_tagged_as_managed_are_rejected(self):
        reader = MagicMock(spec=AWS)
        reader.region = 'us-east-1'
        reader.read.side_effect = [
            {'LocationConstraint': None},
            {'TagSet': [{'Key': 'automqVendor', 'Value': 'automq'}]},
        ]
        ui = MagicMock()
        ui.choose.return_value = {'Name': 'old-managed-data'}
        with tempfile.TemporaryDirectory() as temp:
            wizard = AWSWizard(Path(temp) / 'out', ui=ui)
            wizard.state = fixture()
            wizard.aws = reader
            wizard.option = MagicMock(return_value='existing')
            with self.assertRaisesRegex(SetupError, 'CMP-managed'):
                wizard.data_bucket()

    def test_bucket_reuse_requires_same_region_and_safe_lifecycle(self):
        cases = [
            ('selected Region', [{'LocationConstraint': 'us-west-2'}]),
            ('Bucket lifecycle', [{'LocationConstraint': None}, {'TagSet': []},
                                  {'Rules': [{'Status': 'Enabled', 'Expiration': {'Days': 1}}]}]),
        ]
        for message, responses in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as temp:
                wizard = AWSWizard(Path(temp) / 'out', ui=MagicMock())
                wizard.state = fixture()
                wizard.option = MagicMock(return_value='existing')
                wizard.ui.choose.return_value = {'Name': 'existing-data'}
                wizard.aws = MagicMock(spec=AWS, region='us-east-1')
                wizard.aws.read.side_effect = responses
                with self.assertRaisesRegex(SetupError, message):
                    wizard.data_bucket()
                self.assertIsNone(wizard.state['data_bucket'])

    def test_private_zone_reuse_requires_vpc_association(self):
        with tempfile.TemporaryDirectory() as temp:
            wizard = AWSWizard(Path(temp) / 'out', ui=MagicMock())
            wizard.state = dict(fixture(), dns_mode='private')
            wizard.ui.choose.return_value = {'HostedZoneId': 'ZOTHER'}
            wizard.aws = MagicMock(spec=AWS, region='us-east-1')
            wizard.aws.read.return_value = {
                'HostedZone': {'Id': 'ZOTHER', 'Config': {'PrivateZone': True}},
                'VPCs': [{'VPCId': 'vpc-other', 'VPCRegion': 'us-east-1'}],
            }
            with self.assertRaisesRegex(SetupError, 'associated with this VPC'):
                wizard.dns()

    def test_zones_tagged_as_managed_are_rejected(self):
        reader = MagicMock(spec=AWS)
        reader.region = 'us-east-1'
        reader.read.side_effect = [
            {'HostedZone': {'Id': '/hostedzone/ZTEST', 'Config': {'PrivateZone': True}},
             'VPCs': [{'VPCId': 'vpc-123', 'VPCRegion': 'us-east-1'}]},
            {'ResourceTagSet': {'Tags': [{'Key': 'automqVendor', 'Value': 'automq'}]}},
        ]
        ui = MagicMock()
        ui.choose.return_value = {'HostedZoneId': '/hostedzone/ZTEST'}
        with tempfile.TemporaryDirectory() as temp:
            wizard = AWSWizard(Path(temp) / 'out', ui=ui)
            wizard.state = dict(fixture(), dns_mode='private')
            wizard.aws = reader
            with self.assertRaisesRegex(SetupError, 'CMP-managed'):
                wizard.dns()
        reader.read.assert_called_with('route53', 'list-tags-for-resource', '--resource-type', 'hostedzone',
                                       '--resource-id', 'ZTEST')

    def test_private_zone_mtls_verifies_ca_chain_and_expiry_with_openssl(self):
        def openssl(*args):
            subprocess.run(['openssl', *args], check=True, capture_output=True)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            root_ca, ca_key = root / 'ca.pem', root / 'ca.key'
            openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '60',
                    '-subj', '/CN=Lab CA', '-addext', 'basicConstraints=critical,CA:TRUE',
                    '-keyout', str(ca_key), '-out', str(root_ca))
            csr = root / 'server.csr'
            openssl('req', '-new', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=*.test.internal',
                    '-keyout', str(root / 'server.key'), '-out', str(csr))
            extension = root / 'server.conf'
            extension.write_text('subjectAltName=DNS:*.test.internal\nextendedKeyUsage=serverAuth\n')
            for days, filename in [(60, 'server.pem'), (1, 'expires.pem')]:
                openssl('x509', '-req', '-in', str(csr), '-CA', str(root_ca), '-CAkey', str(ca_key),
                        '-set_serial', str(days), '-days', str(days), '-extfile', str(extension), '-out', str(root / filename))
            verify_server_chain((root / 'server.pem').read_text(), root_ca.read_text(), 'test.internal.')
            answers = iter(['1', str(root / 'server.pem'), str(root / 'server.key'), str(root_ca)])
            wizard = AWSWizard(root / 'out', ui=UI(lambda _: next(answers), lambda _: None))
            wizard.state = dict(fixture(), dns_mode='private', deploy_type='IAAS', auth=['mtls'], transport=['tls'])
            wizard.state['zone']['Name'] = 'test.internal.'
            for step in ('certificate', 'private_key', 'client_ca'):
                self.assertTrue(wizard.node_enabled(step))
                getattr(wizard, step)()
            security = request_body(wizard.state)['features']['security']
            self.assertEqual(security['certificateAuthority'], root_ca.read_text())
            self.assertEqual(security['privateKey'], (root / 'server.key').read_text())
            with self.assertRaisesRegex(SetupError, '30 days'):
                verify_server_chain((root / 'expires.pem').read_text(), root_ca.read_text(), 'test.internal.')
