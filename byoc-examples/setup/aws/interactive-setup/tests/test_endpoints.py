from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from core import SetupError
from endpoints import inspect_endpoints, s3_command


class FakeAWS:
    region = 'us-east-1'

    def __init__(self, endpoints=()):
        self.endpoints = list(endpoints)
        self.tables = [
            {'RouteTableId': 'rtb-main', 'Associations': [{'Main': True}]},
            {'RouteTableId': 'rtb-explicit', 'Associations': [{'SubnetId': 'subnet-a'}]}]

    def read(self, service, operation, *args):
        assert service == 'ec2'
        assert args == ('--filters', 'Name=vpc-id,Values=vpc-test')
        if operation == 'describe-route-tables':
            return {'RouteTables': self.tables}
        if operation == 'describe-vpc-endpoints':
            return {'VpcEndpoints': self.endpoints}
        raise AssertionError(operation)


def gateway(**overrides):
    value = {'VpcEndpointId': 'vpce-test', 'VpcId': 'vpc-test', 'State': 'available',
             'VpcEndpointType': 'Gateway', 'ServiceName': 'com.amazonaws.us-east-1.s3',
             'RouteTableIds': ['rtb-main'], 'PolicyDocument': '{"Statement": []}'}
    value.update(overrides)
    return value


class EndpointTests(unittest.TestCase):
    def test_explicit_and_main_associations_and_coverage(self):
        result = inspect_endpoints(FakeAWS([gateway()]), 'vpc-test', ['subnet-a', 'subnet-b'])
        self.assertEqual(result['subnetRouteTables'], {'subnet-a': 'rtb-explicit', 'subnet-b': 'rtb-main'})
        self.assertEqual(result['s3MissingRouteTables'], ['rtb-explicit'])
        self.assertEqual(result['connectivity'], 'not tested')

    def test_wrong_vpc_region_and_type_do_not_satisfy_s3(self):
        values = [gateway(VpcId='vpc-other'), gateway(ServiceName='com.amazonaws.us-west-2.s3'),
                  gateway(VpcEndpointType='Interface'), gateway(State='deleted')]
        result = inspect_endpoints(FakeAWS(values), 'vpc-test', ['subnet-b'])
        self.assertEqual(result['s3MissingRouteTables'], ['rtb-main'])
        self.assertEqual(result['s3Gateways'], [])

    def test_missing_association_cannot_pass(self):
        aws = FakeAWS()
        aws.tables = []
        with self.assertRaises(SetupError):
            inspect_endpoints(aws, 'vpc-test', ['subnet-b'])

    def test_create_modify_pending_and_stale_command(self):
        state = {'home': {'region': 'us-east-1'}, 'name': 'test', 'vpc': {'VpcId': 'vpc-test'}}
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            result = inspect_endpoints(FakeAWS(), 'vpc-test', ['subnet-a', 'subnet-b'])
            path = s3_command(directory, state, result)
            command = path.read_text()
            self.assertIn('create-vpc-endpoint', command)
            self.assertIn('automq-origin', command)
            self.assertIn('setup-command', command)
            self.assertIn('rtb-explicit rtb-main', command)
            subprocess.run(['bash', '-n', str(path)], check=True)
            result = inspect_endpoints(FakeAWS([gateway()]), 'vpc-test', ['subnet-a', 'subnet-b'])
            command = s3_command(directory, state, result).read_text()
            self.assertIn('--add-route-table-ids rtb-explicit', command)
            self.assertIn('modify-vpc-endpoint', command)
            self.assertNotIn('policy-document', command)
            self.assertNotIn('rtb-main', command)
            pending = inspect_endpoints(FakeAWS([gateway(State='pending')]), 'vpc-test', ['subnet-b'])
            self.assertIsNone(s3_command(directory, state, pending))
            self.assertFalse(path.exists())
            s3_command(directory, state, result)
            complete = inspect_endpoints(FakeAWS([gateway()]), 'vpc-test', ['subnet-b'])
            self.assertIsNone(s3_command(directory, state, complete))
            self.assertFalse(path.exists())

    def test_optional_interfaces_show_configuration_without_claiming_connectivity(self):
        endpoint = gateway(VpcEndpointType='Interface', ServiceName='com.amazonaws.us-east-1.ec2', PrivateDnsEnabled=False)
        result = inspect_endpoints(FakeAWS([endpoint]), 'vpc-test', ['subnet-b'])
        ec2 = next(x for x in result['interfaces'] if x['service'] == 'EC2')
        self.assertEqual(ec2['endpoints'][0]['privateDnsEnabled'], False)
        self.assertEqual(result['connectivity'], 'not tested')
