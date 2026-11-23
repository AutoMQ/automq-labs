import base64
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core import SetupError, policies, request_body
from model import filesystem,listeners
from eks import check_evidence,scheduling,trust
from eks_console import generate_eks_console
from flows import AWSWizard
from setup import UI
from test_setup import fixture


def cluster():
    return {'name':'test-eks','arn':'arn:aws:eks:us-east-1:123456789012:cluster/test-eks','status':'ACTIVE','version':'1.33',
        'resourcesVpcConfig':{'vpcId':'vpc-123','subnetIds':['subnet-123']},'accessConfig':{'authenticationMode':'API'},
        'identity':{'oidc':{'issuer':'https://oidc.eks.us-east-1.amazonaws.com/id/TEST'}}}


def evidence():
    return {'clusterArn':cluster()['arn'],'nodes':{'items':[{'metadata':{'name':'node'},'status':{'conditions':[{'type':'Ready','status':'True'}]}}]},
        'daemonsets':{'items':[{'metadata':{'name':'aws-node'},'status':{'numberReady':1,'desiredNumberScheduled':1}}]},
        'deployments':{'items':[{'metadata':{'name':name},'status':{'availableReplicas':1}} for name in ['aws-load-balancer-controller','ebs-csi-controller','efs-csi-controller']]},
        'storageclasses':{'items':[{'metadata':{'name':x},'provisioner':'ebs.csi.aws.com','volumeBindingMode':'WaitForFirstConsumer','parameters':{'tagSpecification_1':'automqVendor=automq','encrypted':'true' if x.endswith('encrypted') else 'false'}} for x in ['automq-disk-eks-gp3','automq-disk-eks-gp3-encrypted']]},
        'drivers':{'items':[{'metadata':{'name':x}} for x in ['ebs.csi.aws.com','efs.csi.aws.com']]}}


class CompleteModelTests(unittest.TestCase):
    def test_capacity_limits(self):
        self.assertEqual(filesystem(200,'ONTAP_V2')['fileSystemCount'],2)
        self.assertEqual(filesystem(2500,'ONTAP_V2')['throughputMiBpsPerFileSystem'],768)
        self.assertEqual(filesystem(1,'EFS_PROVISIONED')['throughputMiBpsPerFileSystem'],11)
        for value,kind in [(9601,'ONTAP_V2'),(407,'EFS_PROVISIONED')]:
            with self.assertRaises(SetupError): filesystem(value,kind)

    def test_security_combinations(self):
        self.assertEqual(len(listeners(['plaintext','tls'],['sasl','anonymous','mtls'])),4)
        for t,a in [(['tls'],['anonymous']),(['plaintext'],['mtls']),(['tls'],[])]:
            with self.assertRaises(SetupError): listeners(t,a)

    def test_eks_request_and_policy_are_scoped(self):
        state=fixture();state.update(deploy_type='K8S',eks=cluster(),namespace='automq',service_account='automq-sa',
            lb_subnets=[state['subnet']],wal='FSWAL',filesystem=filesystem(100,'EFS_PROVISIONED'),
            data_bucket='existing-data',node_count=6,metrics={'enabled':True,'authType':'sigv4','prometheusArn':'arn:aws:aps:us-east-1:123456789012:workspace/ws-test'},
            dns_mode='public',public_dns={'crossAccountRole':'arn:aws:iam::999999999999:role/dns'})
        body=request_body(state)
        self.assertEqual(body['spec']['deployType'],'K8S')
        self.assertEqual(body['spec']['kubernetesClusterId'],'test-eks')
        self.assertNotIn('dnsZone',body['spec'])
        self.assertEqual(body['features']['walMode'],'FSWAL')
        c,p=policies(state)
        text=json.dumps(p)
        self.assertNotIn('ec2:RunInstances',text)
        self.assertNotIn('fsx:CreateFileSystem',text)
        self.assertIn('elasticfilesystem:CreateFileSystem',text)
        self.assertIn('existing-data',text)
        self.assertNotIn('automq-data-*',text)
        self.assertIn('aps:RemoteWrite',json.dumps(c))
        self.assertNotIn('<',text)

    def test_evidence_and_scheduling(self):
        self.assertEqual(check_evidence(evidence(),cluster(),'FSWAL')['readyNodes'],1)
        broken=evidence();broken['drivers']['items']=[]
        with self.assertRaises(SetupError): check_evidence(broken,cluster(),'EBSWAL')
        self.assertEqual(json.loads(scheduling('{"tolerations": []}')),{'tolerations':[]})
        with self.assertRaises(SetupError): scheduling('{"nodeSelector": {}}')
        self.assertIn('AssumeRoleWithWebIdentity',json.dumps(trust(fixture(),cluster(),'automq','automq-sa','irsa')))

    def test_cluster_storageclasses_are_not_required_or_validated(self):
        data=evidence()
        data.pop('storageclasses')
        self.assertEqual(check_evidence(data,cluster(),'EBSWAL')['readyNodes'],1)
        data['storageclasses']={'items':[{'metadata':{'name':'automq-disk-eks-gp3-encrypted'},'parameters':{}}]}
        self.assertEqual(check_evidence(data,cluster(),'EBSWAL')['readyNodes'],1)
        from eks import evidence_command, component_commands
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)
            self.assertNotIn('storageclasses',evidence_command(path,fixture(),cluster(),'automq-eks').read_text())
            self.assertNotIn('automq-disk-eks',component_commands(path,dict(fixture(),wal='EBSWAL'),cluster(),data,'automq-eks').read_text())

    def test_eks_console_renders_and_keeps_credentials_out_of_values(self):
        state=fixture();state.update(console_eks=cluster(),console_password='TEST_PASSWORD',api_credentials={'accessKey':'TEST_AK','secretKey':'TEST_SK'})
        state['home'].update(config='ENCODED_CONFIG',image='automq.azurecr.io/automq/automq-byoc-console:8.4.7-aws')
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp);generate_eks_console(path,state)
            for file in path.glob('*.sh'): subprocess.run(['bash','-n',str(file)],check=True)
            rendered=subprocess.run(['helm','template','automq-console',str(path/'console-chart'),'--namespace','automq-console','--values',str(path/'console-values.json')],capture_output=True,text=True,check=True).stdout
            for literal in ['CONSOLE_INITIAL_ACCESS_KEY','CONSOLE_INITIAL_SECRET_KEY','secretKeyRef','mountPath: /data','name: automq-console']:
                self.assertIn(literal,rendered)
            import yaml
            services=[doc['metadata']['name'] for doc in yaml.safe_load_all(rendered) if doc and doc.get('kind')=='Service']
            self.assertEqual(len(services),1)
            self.assertIn('service/'+services[0],(path/'access-console.sh').read_text())
            for secret in ['TEST_PASSWORD','TEST_AK','TEST_SK','ENCODED_CONFIG']: self.assertNotIn(secret,rendered)
            self.assertNotIn('value: "admin"\n            - name: CLOUD_PROVIDER',rendered)
            for file in path.rglob('*'):
                if file.is_file(): self.assertEqual(file.stat().st_mode & 0o777,0o600)

class FullAWSStories(unittest.TestCase):
    def test_complete_ec2_and_eks_stories(self):
        for deploy,console_new,wal,az_count,dns,binding,existing in [
            ('IAAS',False,'EBSWAL',1,'private','pod',False),
            ('IAAS',True,'S3WAL',3,'private','pod',False),
            ('K8S',False,'EBSWAL',1,'private','pod',False),
            ('K8S',True,'FSWAL',3,'private','pod',False),
            ('IAAS',False,'FSWAL',3,'public','pod',True),
            ('K8S',True,'S3WAL',3,'public','irsa',True)]:
            with self.subTest(deploy=deploy,new=console_new,wal=wal),tempfile.TemporaryDirectory() as temp:
                directory=Path(temp);evidence_path=directory/'evidence.json';evidence_path.write_text(json.dumps(evidence()))
                vpc={'VpcId':'vpc-123','CidrBlock':'10.0.0.0/16','State':'available'}
                subnets=[{'SubnetId':f'subnet-{i}','VpcId':'vpc-123','State':'available','AvailabilityZone':f'us-east-1{letter}',
                    'AvailabilityZoneId':f'use1-az{i}','CidrBlock':f'10.0.{i}.0/24','AvailableIpAddressCount':200} for i,letter in enumerate('abc',1)]
                eks_cluster=cluster();eks_cluster['resourcesVpcConfig']['subnetIds']=[x['SubnetId'] for x in subnets]
                evidence_path.write_text(json.dumps({**evidence(),'clusterArn':eks_cluster['arn']}))
                roles=[{'RoleName':name,'Arn':f'arn:aws:iam::123456789012:role/{name}','AssumeRolePolicyDocument':{'Statement':[{'Effect':'Allow','Principal':{'Service':'ec2.amazonaws.com'},'Action':'sts:AssumeRole'}]}} for name in ['cluster','console']]
                calls=[]
                class FakeAWS:
                    def __init__(self,region): self.region=region
                    def read(self,service,op,*args):
                        calls.append((service,op))
                        def arg(name): return args[args.index(name)+1]
                        if op=='get-caller-identity': return {'Account':'123456789012'}
                        if op=='describe-vpcs': return {'Vpcs':[vpc]}
                        if op=='describe-subnets': return {'Subnets':subnets}
                        if op=='describe-vpc-attribute': return {'EnableDnsHostnames':{'Value':True},'EnableDnsSupport':{'Value':True}}
                        if op=='describe-instance-type-offerings': return {'InstanceTypeOfferings':[{'InstanceType':x} for x in ['r6i.large','m7g.xlarge','t3.large']]}
                        if op=='describe-images': return {'Images':[{'ImageId':'ami-test','RootDeviceName':'/dev/xvda','Architecture':'x86_64','State':'available'}]}
                        if op=='get-parameter': return {'Parameter':{'Value':'ami-test'}}
                        if op=='list-hosted-zones-by-vpc': return {'HostedZoneSummaries':[{'Name':'test.internal.','HostedZoneId':'ZTEST'}]}
                        if op=='get-hosted-zone': return {'HostedZone':{'Id':'/hostedzone/ZTEST','Name':'test.internal.','Config':{'PrivateZone':True}},'VPCs':[{'VPCId':'vpc-123','VPCRegion':'us-east-1'}]}
                        if op=='list-tags-for-resource': return {'ResourceTagSet': {'Tags': []}}
                        if op=='describe-security-groups': return {'SecurityGroups':[{'GroupName':'console','GroupId':'sg-test','VpcId':'vpc-123','IpPermissions':[{'IpProtocol':'-1','IpRanges':[{'CidrIp':'10.0.0.0/16'}]}],'IpPermissionsEgress':[]}]}
                        if op=='describe-key-pairs': return {'KeyPairs':[{'KeyName':'key','KeyPairId':'key-id'}]}
                        if op=='list-buckets': return {'Buckets':[{'Name':'existing-data'}]}
                        if op=='get-bucket-location': return {'LocationConstraint':None}
                        if op=='get-bucket-tagging': return {'TagSet':[]}
                        if op=='get-bucket-lifecycle-configuration': return {'Rules':[]}
                        if op=='get-open-id-connect-provider': return {'ClientIDList':['sts.amazonaws.com']}
                        if op=='list-roles': return {'Roles':roles}
                        if op=='get-role': return {'Role':next(r for r in roles if r['RoleName']==arg('--role-name'))}
                        if op=='list-instance-profiles-for-role': return {'InstanceProfiles':[{'Arn':'arn:aws:iam::123456789012:instance-profile/test'}]}
                        if op=='list-attached-role-policies': return {'AttachedPolicies':[]}
                        if op=='describe-route-tables': return {'RouteTables':[{'RouteTableId':'rtb-test','Associations':[{'Main':True}]}]}
                        if op=='describe-vpc-endpoints': return {'VpcEndpoints':[{'VpcEndpointId':'vpce-test','VpcId':'vpc-123','ServiceName':'com.amazonaws.us-east-1.s3','VpcEndpointType':'Gateway','State':'available','RouteTableIds':['rtb-test']}]}
                        if op=='list-clusters': return {'clusters':['test-eks']}
                        if op=='describe-cluster': return {'cluster':eks_cluster}
                        if op=='list-nodegroups': return {'nodegroups':['group']}
                        if op=='describe-nodegroup': return {'nodegroup':{'nodegroupName':'group','status':'ACTIVE','instanceTypes':['r6i.large','m7g.xlarge'],'subnets':[x['SubnetId'] for x in subnets],'scalingConfig':{'maxSize':10,'desiredSize':4},'taints':[]}}
                        if op=='list-addons': return {'addons':['eks-pod-identity-agent']}
                        if op=='describe-addon': return {'addon':{'status':'ACTIVE'}}
                        if op=='list-pod-identity-associations': return {'associations':[]}
                        if op=='list-access-entries': return {'accessEntries':[roles[1]['Arn']]}
                        if op=='describe-access-entry': return {'accessEntry':{'type':'STANDARD'}}
                        if op=='list-associated-access-policies': return {'associatedAccessPolicies':[{'policyArn':'arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy','accessScope':{'type':'cluster'}}]}
                        raise AssertionError((service,op,args))
                class AutoUI(UI):
                    def __init__(self): super().__init__(show=lambda _:None);self.multi_count=0;self.role_count=0
                    def section(self,title): self.last_title=title
                    def confirm(self,text): pass
                    def preparation(self,*args,**kwargs): return 'b'
                    def choose(self,title,fetch,label,identity,current=None,prepare=None,refresh=True):
                        rows=fetch()
                        preferred={'Console environment':'new' if console_new else 'existing','Run AutoMQ on':deploy,
                            'Availability-zone layout':str(az_count),'WAL storage':wal,'DNS mode':dns,'AWS workload identity':binding,
                            'Data Bucket':'existing' if existing else 'managed','Security group preparation':'existing' if existing else 'managed',
                            'Prometheus Remote Write':'noauth' if existing else 'off','Schema Registry':'on' if existing else 'off','Install Console on':'K8S' if deploy=='K8S' else 'IAAS'}
                        if title in preferred and isinstance(rows[0],tuple): return next(x for x in rows if identity(x)==preferred[title])
                        if title=='Select Role' or title=='IAM Role':
                            value=rows[self.role_count];self.role_count+=1;return value
                        if title=='Instance type available in every selected AZ': return next(x for x in rows if x['type']==('m7g.xlarge' if wal=='S3WAL' else 'r6i.large'))
                        return rows[0]
                    def prompt(self,text,current=None):
                        if text.startswith('Cluster name'): return 'full-story'
                        if text.startswith('Expected peak'): return '10'
                        if text.startswith('Total node'): return '3'
                        if text.startswith('Optional cluster'): return ''
                        if 'JSON name/value' in text: return '[]'
                        if text=='Remote Write URL': return 'https://metrics.example/api/v1/write'
                        if text.startswith('Collected evidence'): return str(evidence_path)
                        if text.startswith('CIDR'): return '10.0.0.0/16'
                        if text.startswith('Enter numbers'):
                            self.multi_count+=1
                            # compute subnet first, transport/auth next, EFS subnets last, Console subnet last for EC2/existing.
                            if self.last_title in ['Compute subnets','EFS mount-target subnets','NLB subnets']: return ','.join(str(i) for i in range(1,az_count+1))
                            return '1'
                        return current or ''
                home={'environmentId':'env-test','clientId':'id','clientSecret':'SECRET_HOME','region':'us-east-1','opsBucket':{'bucketName':'ops-test'}}
                encoded=base64.b64encode(json.dumps(home).encode()).decode()
                command=f'docker run -e CONFIG={encoded} -e CLOUD_PROVIDER=aws automq.azurecr.io/automq/automq-byoc-console:8.4.7-aws'
                with patch('setup.read_home_command',return_value=command),patch('getpass.getpass',return_value='LONG_TEST_PASSWORD'),patch('home.prepare_public_dns',return_value={'hostedZoneId':'ZPUBLIC','crossAccountRole':'arn:aws:iam::999999999999:role/dns'}):
                    wizard=AWSWizard(directory/'out',AutoUI(),FakeAWS,home_reader=lambda _: {'available':True})
                    # Turn unexpected validation errors into test failures instead of retrying forever.
                    wizard.ui.show=lambda text: (_ for _ in ()).throw(AssertionError(text)) if str(text).startswith('\nERROR:') else None
                    state=wizard.run()
                output=directory/'out'
                body=json.loads((output/'cluster-request.json').read_text())
                self.assertEqual(body['spec']['deployType'],deploy)
                self.assertEqual(body['features']['walMode'],wal)
                self.assertEqual(len(body['spec']['networks']),az_count)
                for file in output.glob('*.sh'): subprocess.run(['bash','-n',str(file)],check=True)
                self.assertNotIn('SECRET_HOME',(output/'review.json').read_text())
                if deploy=='K8S': self.assertEqual(body['spec']['kubernetesServiceAccount'],'automq-sa')
                if console_new and deploy=='K8S': self.assertTrue((output/'install-console-eks.sh').exists())

class BoundaryTests(unittest.TestCase):
    def test_real_pem_validation_and_wrong_key(self):
        from certificates import certificate_info,validate_key
        with tempfile.TemporaryDirectory() as temp:
            p=Path(temp)
            for name in ['one','two']:
                subprocess.run(['openssl','req','-x509','-newkey','rsa:2048','-nodes','-keyout',str(p/(name+'.key')),
                    '-out',str(p/(name+'.crt')),'-days','1','-subj','/CN=*.test.internal','-addext','subjectAltName=DNS:*.test.internal'],capture_output=True,check=True)
            cert=(p/'one.crt').read_text(); key=(p/'one.key').read_text()
            certificate_info(cert,'test.internal.')
            validate_key(cert,key)
            with self.assertRaises(SetupError): certificate_info(cert,'different.internal')
            with self.assertRaises(SetupError): validate_key(cert,(p/'two.key').read_text())

    def test_public_dns_metrics_fsx_request(self):
        state=fixture();state.update(dns_mode='public',public_dns={'crossAccountRole':'arn:aws:iam::999999999999:role/dns'},
            wal='FSWAL',filesystem=filesystem(2500,'ONTAP_V2'),transport=['tls'],auth=['sasl','mtls'],tls_material={'certificateAuthority':'CA'},
            metrics={'enabled':True,'authType':'noauth','endPoint':'https://metrics.example/api/v1/write','labels':[]},
            schema=True,tags=[{'name':'team','value':'streaming'}])
        body=request_body(state)
        self.assertEqual(body['features']['metricsExporter']['prometheus']['authType'],'noauth')
        self.assertEqual(body['spec']['fileSystemForFsWal']['fileSystemCount'],9)
        c,p=policies(state)
        self.assertIn('fsx:CreateFileSystem',json.dumps(p))
        self.assertNotIn('elasticfilesystem:CreateFileSystem',json.dumps(p))
        self.assertIn('arn:aws:iam::999999999999:role/dns',json.dumps(c))
        self.assertNotIn('<',json.dumps(p))

    def test_sg_commands_include_internal_and_selected_client_ports(self):
        from resources import sg_rules,sg_command,bucket_command
        state=fixture();state.update(auth=['sasl'],listeners=listeners(['tls'],['sasl']),schema=True)
        state['vpc']['CidrBlock']='10.0.0.0/16'
        rules=sg_rules(state)
        self.assertEqual({x[0] for x in rules},{22,9090,9102,9103,9112,8081})
        with tempfile.TemporaryDirectory() as temp:
            for path in [sg_command(Path(temp),state,'cluster-sg',rules),bucket_command(Path(temp),state)]:
                subprocess.run(['bash','-n',str(path)],check=True)
                self.assertNotIn('put-bucket-lifecycle',path.read_text())

    def test_missing_components_generate_separate_roles(self):
        from eks import component_commands
        state=fixture();state.update(wal='FSWAL')
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp); command=component_commands(path,state,cluster(),{},'test')
            text=command.read_text()
            for value in ['aws-ebs-csi-driver','aws-efs-csi-driver','aws-load-balancer-controller','1.10.0']:
                self.assertIn(value,text)
            self.assertNotIn('--override-existing-serviceaccounts',text)
            self.assertFalse(list(path.glob('automq-disk-eks-*')))
            subprocess.run(['bash','-n',str(command)],check=True)
