"""AWS decision constraints and CMP request mapping."""
import copy
import json
import math
from core import SetupError


def cluster_version(home):
    image_tag = home.get('image', '').rpartition(':')[2]
    return '5.5.9' if image_tag == '8.4.13-aws' else '5.5.6'


def load_instance_configs(path):
    def unique_keys(pairs):
        values = {}
        for key, value in pairs:
            if key in values:
                raise SetupError('Instance config keys must be unique.')
            values[key] = value
        return values

    try:
        configs = json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique_keys)
    except (OSError, ValueError):
        raise SetupError('Read a UTF-8 JSON file containing instance config key/value pairs.') from None
    if not isinstance(configs, dict) or any(
        not key or key != key.strip() or not isinstance(value, str)
        for key, value in configs.items()
    ):
        raise SetupError('Instance configs require a JSON object with non-empty keys and string values.')
    return configs


def filesystem(peak, kind):
    if kind == 'EFS_PROVISIONED':
        throughput = max(10, math.ceil(2.5 * peak + 8))
        if throughput > 1024:
            raise SetupError('EFS requires more than the supported 1024 MiB/s. Go Back to change WAL or peak demand.')
        return {'fileSystemType': kind, 'throughputMiBpsPerFileSystem': throughput, 'fileSystemCount': 1}
    for throughput, capacity in [(384, 150), (768, 300), (1536, 600)]:
        count = math.ceil(peak / capacity)
        if count <= 16:
            return {'fileSystemType': 'ONTAP_V2', 'throughputMiBpsPerFileSystem': throughput, 'fileSystemCount': count}
    raise SetupError('FSx demand exceeds 9600 MiB/s of AutoMQ BytesIn.')


def listeners(transport, auth):
    t, a = set(transport), set(auth)
    if not t or not a or t - {'plaintext', 'tls'} or a - {'sasl', 'anonymous', 'mtls'}:
        raise SetupError('Choose at least one supported transport and authentication method.')
    if ('plaintext' in t and not a & {'sasl', 'anonymous'} or
        'tls' in t and not a & {'sasl', 'mtls'} or
        'anonymous' in a and 'plaintext' not in t or 'mtls' in a and 'tls' not in t):
        raise SetupError('Incompatible transport/authentication combination. Anonymous requires plaintext; mTLS requires TLS; TLS needs SASL or mTLS.')
    return [{'protocol': p, 'port': port} for trans, method, p, port in [
        ('plaintext', 'sasl', 'SASL_PLAINTEXT', 9102), ('plaintext', 'anonymous', 'PLAINTEXT', 9092),
        ('tls', 'sasl', 'SASL_SSL', 9112), ('tls', 'mtls', 'SSL', 9122)] if trans in t and method in a]


def request(state):
    networks = state.get('subnets', [state['subnet']])
    spec = {'pricingMode': 'UsageBased', 'reservedNodeCount': state.get('node_count', 3),
            'nodeConfig': {**state.get('payment', {'paymentType': 'ON_DEMAND'}), 'instanceTypes': [state['instance_type']]},
            'provider': 'aws', 'region': state['home']['region'], 'scope': state['account'],
            'vpc': state['vpc']['VpcId'], 'deployType': state.get('deploy_type', 'IAAS'),
            'networks': [{'zone': x['AvailabilityZone'], 'zoneId': x['AvailabilityZoneId'], 'subnet': x['SubnetId']} for x in networks],
            'dataBuckets': [{'bucketName': state['data_bucket']}] if state.get('data_bucket') else [],
            'instanceRole': state['cluster_role']['RoleName']}
    if state.get('dns_mode') == 'public':
        spec['dnsZoneType'] = 'PUBLIC'
    else:
        spec['dnsZone'] = state['zone']['Id'].split('/')[-1]
    if state.get('cluster_security_groups'):
        spec['securityGroups'] = [x['GroupId'] for x in state['cluster_security_groups']]
    if state.get('filesystem'):
        spec['fileSystemForFsWal'] = copy.deepcopy(state['filesystem'])
    if spec['deployType'] == 'K8S':
        spec.update(kubernetesClusterId=state['eks']['name'], kubernetesNamespace=state['namespace'],
                    kubernetesServiceAccount=state['service_account'],
                    kubernetesLoadBalancerSubnets=[x['SubnetId'] for x in state['lb_subnets']])
        if state.get('schedule'):
            spec['scheduleSpec'] = state['schedule']
    security = {'dataEncryptionMode': 'CPMK', 'authenticationMethods': state.get('auth', ['sasl']),
                'transitEncryptionModes': state.get('transport', ['plaintext']), 'tlsHostnameValidationEnabled': True}
    security.update(state.get('tls_material', {}))
    features = {'walMode': state.get('wal', 'EBSWAL'), 'schemaRegistryEnabled': state.get('schema', False), 'security': security}
    if state.get('metrics'):
        features['metricsExporter'] = {'prometheus': copy.deepcopy(state['metrics'])}
    if state.get('instance_configs'):
        features['instanceConfigs'] = [
            {'key': key, 'value': value} for key, value in state['instance_configs'].items()
        ]
    body = {'name': state['name'], 'version': cluster_version(state['home']), 'spec': spec, 'features': features}
    if state.get('description'):
        body['description'] = state['description']
    if state.get('tags'):
        body['tags'] = state['tags']
    return body
