#!/usr/bin/env python3
"""Explicit opt-in AWS preparation smoke test. No CMP or AutoMQ creation request.
Creates an isolated VPC and prerequisites, executes generated scripts, always cleans up.
Run: python live_aws_precreate.py --run --region us-east-1 --output NEW_DIRECTORY
"""
import argparse
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import time
import uuid
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from core import AWS, policies, role_commands, tags, write_private, zone_commands
from resources import bucket_command, sg_command, sg_rules
from endpoints import inspect_endpoints,s3_command
from model import listeners


class Probe:
    def __init__(self,region,directory):
        self.region=region;self.directory=directory;directory.mkdir(mode=0o700,parents=True,exist_ok=False)
        self.entries=[];self.results=[];self.name='verify-'+uuid.uuid4().hex[:8]
        self.account=None;self.vpc=None

    def save(self):
        write_private(self.directory/'resources.json',self.entries)
        write_private(self.directory/'results.json',self.results)

    def record(self,kind,identifier):
        item={'kind':kind,'id':identifier,'status':'created-or-planned'};self.entries.append(item);self.save();return item

    def run(self,args,check=True):
        with (self.directory/'commands.log').open('a') as log:
            os.chmod(log.name,0o600);log.write('$ '+shlex.join(args)+'\n');log.flush()
            result=subprocess.run(args,capture_output=True,text=True,timeout=180,env={**os.environ,'AWS_PAGER':'','AWS_CLI_AUTO_PROMPT':'off'})
            log.write(result.stdout+result.stderr+f'\nexit={result.returncode}\n')
        if check and result.returncode: raise RuntimeError(f'Command failed: {args[0]} {args[1:3]}; see private commands.log')
        return result

    def aws(self,service,action,*args,check=True):
        result=self.run(['aws',service,action,'--region',self.region,'--no-cli-pager','--output','json','--cli-connect-timeout','10','--cli-read-timeout','30',*args],check)
        if result.returncode and not check and not any('('+code+')' in result.stderr for code in ['NoSuchLifecycleConfiguration','NoSuchEntity','NoSuchBucket']):
            raise RuntimeError(f'{service}:{action} failed; absence has not been established. See commands.log')
        return json.loads(result.stdout) if result.returncode==0 and result.stdout.strip() else {}

    def execute(self,path):
        print('Execute generated file:',path.name,flush=True)
        self.run(['bash',str(path)])

    def test(self):
        identity=self.aws('sts','get-caller-identity');self.account=identity['Account']
        self.results.append({'check':'identity','account':self.account,'region':self.region});self.save()
        spec=json.dumps([{'ResourceType':'vpc','Tags':[{'Key':'Name','Value':self.name}]+tags(self.name,'precreate-test')}])
        self.vpc=self.aws('ec2','create-vpc','--cidr-block','10.253.0.0/16','--tag-specifications',spec)['Vpc']
        self.record('vpc',self.vpc['VpcId'])
        self.aws('ec2','modify-vpc-attribute','--vpc-id',self.vpc['VpcId'],'--enable-dns-hostnames','Value=true')
        self.aws('ec2','wait','vpc-available','--vpc-ids',self.vpc['VpcId'])
        zones=self.aws('ec2','describe-availability-zones','--filters','Name=state,Values=available')['AvailabilityZones'][:3]
        subnets=[]
        for i,zone in enumerate(zones):
            spec=json.dumps([{'ResourceType':'subnet','Tags':tags(self.name,'precreate-test')}])
            subnet=self.aws('ec2','create-subnet','--vpc-id',self.vpc['VpcId'],'--availability-zone',zone['ZoneName'],'--cidr-block',f'10.253.{i}.0/24','--tag-specifications',spec)['Subnet']
            self.record('subnet',subnet['SubnetId']);subnets.append(subnet)
        state={'account':self.account,'home':{'region':self.region,'environmentId':'offline-precreate-test','opsBucket':{'bucketName':'unused-precreate-ops'}},
            'name':self.name,'vpc':self.vpc,'subnet':subnets[0],'subnets':subnets,'listeners':listeners(['plaintext'],['sasl']),'auth':['sasl']}
        bucket=f'automq-setup-{self.name}-{self.account}-{self.region}'
        self.record('bucket',bucket);self.execute(bucket_command(self.directory,state))
        self.aws('s3api','head-bucket','--bucket',bucket)
        lifecycle=self.aws('s3api','get-bucket-lifecycle-configuration','--bucket',bucket,check=False)
        if lifecycle.get('Rules'): raise RuntimeError('Unexpected lifecycle rules on generated Bucket')
        self.results.append({'check':'generated-bucket','id':bucket,'lifecycleRules':lifecycle.get('Rules',[])})
        name=f'automq-setup-{self.name}-cluster-sg';sg_entry=self.record('security-group-name',name)
        self.execute(sg_command(self.directory,state,'cluster-sg',sg_rules(state)))
        groups=self.aws('ec2','describe-security-groups','--filters',f'Name=vpc-id,Values={self.vpc["VpcId"]}',f'Name=group-name,Values={name}')['SecurityGroups']
        sg_entry.update(kind='security-group',id=groups[0]['GroupId']);self.save()
        from resources import validate_sg
        validate_sg(groups[0],self.vpc['VpcId'],sg_rules(state))
        for purpose in ['cluster-role','console-role']:
            role=f'automq-setup-{self.name}-{purpose}'
            self.record('role',role);self.record('instance-profile',role)
            self.execute(role_commands(self.directory,self.region,self.name,purpose))
            state['cluster_role' if purpose=='cluster-role' else 'console_role']=self.aws('iam','get-role','--role-name',role)['Role']
            profile=self.aws('iam','list-instance-profiles-for-role','--role-name',role)['InstanceProfiles']
            if len(profile)!=1: raise RuntimeError('New Role did not expose exactly one generated Instance Profile; retry after IAM propagation.')
            self.results.append({'check':'generated-role-profile','role':role,'profileCount':len(profile)})
        # Zone caller reference/name are recorded before executing the generated creation command.
        zone_entry=self.record('zone-name',self.name+'.automq.internal.')
        self.execute(zone_commands(self.directory,state))
        matches=[z for z in self.aws('route53','list-hosted-zones-by-name','--dns-name',zone_entry['id'])['HostedZones'] if z['Name']==zone_entry['id']]
        zone=matches[0];zone_entry.update(kind='zone',id=zone['Id']);state['zone']=zone;self.save()
        endpoint_entry=self.record('gateway-vpc',self.vpc['VpcId'])
        client=AWS(self.region)
        discovered=inspect_endpoints(client,self.vpc['VpcId'],[x['SubnetId'] for x in subnets])
        self.execute(s3_command(self.directory,state,discovered))
        for attempt in range(30):
            discovered=inspect_endpoints(client,self.vpc['VpcId'],[x['SubnetId'] for x in subnets])
            if not discovered['s3MissingRouteTables']: break
            time.sleep(2)
        else: raise RuntimeError('S3 Gateway did not become available')
        endpoint_entry.update(kind='gateway',id=discovered['s3Gateways'][0]['VpcEndpointId']);self.save()
        self.results.append({'check':'s3-gateway-coverage','subnets':discovered['subnetRouteTables'],'endpoint':endpoint_entry['id']})
        # AWS validates actual generated IAM policy syntax/actions without granting it to a runtime.
        for name,policy in zip(['cluster','console'],policies(state)):
            path=self.directory/(name+'-policy.json');write_private(path,policy)
            result=self.aws('accessanalyzer','validate-policy','--policy-document','file://'+str(path),'--policy-type','IDENTITY_POLICY')
            errors=[x for x in result.get('findings',[]) if x['findingType']=='ERROR']
            self.results.append({'check':'aws-policy-validation','policy':name,'errors':errors,'findings':result.get('findings',[])})
            if errors: raise RuntimeError('AWS rejected generated '+name+' Policy')
        existing=self.aws('eks','list-clusters')['clusters']
        self.results.append({'check':'existing-eks-discovery','clusters':existing,'mutations':'none'})
        for name in existing:
            cluster=self.aws('eks','describe-cluster','--name',name)['cluster']
            self.results.append({'check':'existing-eks-read','name':name,'status':cluster['status'],'version':cluster['version'],'vpc':cluster['resourcesVpcConfig']['vpcId']})
        self.save()

    def cleanup(self):
        for item in reversed(self.entries):
            if item['status']=='deleted': continue
            kind,identifier=item['kind'],item['id']
            try:
                if kind=='gateway': self.aws('ec2','delete-vpc-endpoints','--vpc-endpoint-ids',identifier)
                elif kind=='gateway-vpc':
                    rows=self.aws('ec2','describe-vpc-endpoints','--filters',f'Name=vpc-id,Values={identifier}')['VpcEndpoints']
                    for row in rows: self.aws('ec2','delete-vpc-endpoints','--vpc-endpoint-ids',row['VpcEndpointId'])
                elif kind in ['zone','zone-name']:
                    ids=[identifier] if kind=='zone' else [z['Id'] for z in self.aws('route53','list-hosted-zones-by-name','--dns-name',identifier)['HostedZones'] if z['Name']==identifier]
                    for zid in ids: self.aws('route53','delete-hosted-zone','--id',zid)
                elif kind=='instance-profile':
                    profiles=self.aws('iam','get-instance-profile','--instance-profile-name',identifier,check=False)
                    if profiles:
                        for role in profiles['InstanceProfile']['Roles']: self.aws('iam','remove-role-from-instance-profile','--instance-profile-name',identifier,'--role-name',role['RoleName'])
                        self.aws('iam','delete-instance-profile','--instance-profile-name',identifier)
                elif kind=='role':
                    if self.aws('iam','get-role','--role-name',identifier,check=False): self.aws('iam','delete-role','--role-name',identifier)
                elif kind=='security-group': self.aws('ec2','delete-security-group','--group-id',identifier)
                elif kind=='security-group-name':
                    rows=self.aws('ec2','describe-security-groups','--filters',f'Name=vpc-id,Values={self.vpc["VpcId"]}',f'Name=group-name,Values={identifier}')['SecurityGroups']
                    for row in rows:self.aws('ec2','delete-security-group','--group-id',row['GroupId'])
                elif kind=='bucket': self.aws('s3api','delete-bucket','--bucket',identifier)
                elif kind=='subnet': self.aws('ec2','delete-subnet','--subnet-id',identifier)
                elif kind=='vpc':
                    for attempt in range(15):
                        result=self.run(['aws','ec2','delete-vpc','--region',self.region,'--vpc-id',identifier,'--no-cli-pager'],check=False)
                        if result.returncode==0:break
                        time.sleep(2)
                    else:raise RuntimeError('VPC deletion failed')
                item['status']='deleted'
            except Exception as error:
                item['status']='cleanup-failed';item['error']=str(error)
            self.save()
        return all(x['status']=='deleted' for x in self.entries)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run',action='store_true',required=True);parser.add_argument('--region',required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();probe=Probe(args.region,args.output.resolve());success=False
    try:
        probe.test();success=True
    finally:
        cleaned=probe.cleanup()
        probe.results.append({'testCompleted':success,'cleanupCompleted':cleaned,'cmpCreateRequestSent':False});probe.save()
        print(json.dumps(probe.results[-1]),flush=True)
    return 0 if success and cleaned else 1

if __name__=='__main__':sys.exit(main())
