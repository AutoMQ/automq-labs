"""EKS read-only checks and user-executed preparations."""
import json
import shlex
from core import SetupError, aws_command, tags, write_private
from resources import script


def kubectl(cluster,*args):
    return shlex.join(['kubectl','--context',cluster['arn'],*args])


def validate_cluster(cluster,vpc):
    if cluster['status']!='ACTIVE' or cluster['resourcesVpcConfig']['vpcId']!=vpc:
        raise SetupError('Select an ACTIVE EKS cluster in the selected VPC.')
    if cluster.get('accessConfig',{}).get('authenticationMode') not in ['API','API_AND_CONFIG_MAP']:
        raise SetupError('EKS must enable API or API_AND_CONFIG_MAP authentication for Console Access Entries.')


def evidence_command(directory,state,cluster,purpose):
    queries={'nodes':['get','nodes','-o','json'],'daemonsets':['-n','kube-system','get','daemonsets','-o','json'],
             'deployments':['-n','kube-system','get','deployments','-o','json'],'drivers':['get','csidrivers','-o','json']}
    if purpose=='automq-eks' and state.get('capacity_mode')=='karpenter':
        queries.update(nodepools=['get','nodepools.karpenter.sh','-o','json'],nodeclasses=['get','ec2nodeclasses.karpenter.k8s.aws','-o','json'])
    lines=[aws_command(state['home']['region'],'eks','update-kubeconfig','--name',cluster['name'],'--alias',cluster['arn'])]
    for key,args in queries.items(): lines.append(kubectl(cluster,*args)+f' > {purpose}-{key}.json')
    lines += ["python3 - <<'PY_EVIDENCE'",'import json','from pathlib import Path',f'result = {{"clusterArn": {cluster["arn"]!r}}}']
    for key in queries: lines.append(f'result[{key!r}] = json.loads(Path({(purpose+"-"+key+".json")!r}).read_text())')
    lines += [f'Path({(purpose+"-evidence.json")!r}).write_text(json.dumps(result, indent=2))','PY_EVIDENCE']
    return script(directory,f'collect-{purpose}-evidence.sh',lines)


def check_evidence(data,cluster,wal,console=False):
    if data.get('clusterArn')!=cluster['arn']: raise SetupError('Evidence belongs to another EKS cluster.')
    def names(key): return {x['metadata']['name']:x for x in data.get(key,{}).get('items',[])}
    ds=names('daemonsets'); deployments=names('deployments'); drivers=names('drivers')
    if 'aws-node' not in ds: raise SetupError('Amazon VPC CNI aws-node is required; Pod IPs must come from VPC subnets.')
    status=ds['aws-node'].get('status',{})
    if status.get('numberReady',0)<max(1,status.get('desiredNumberScheduled',1)): raise SetupError('VPC CNI is not Ready on all intended nodes.')
    required=['ebs.csi.aws.com']+(['efs.csi.aws.com'] if wal=='FSWAL' and not console else [])
    if any(x not in drivers for x in required): raise SetupError('Required CSI drivers: '+', '.join(required))
    controllers=['ebs-csi-controller']+(['efs-csi-controller'] if wal=='FSWAL' and not console else [])
    for name in controllers:
        if deployments.get(name,{}).get('status',{}).get('availableReplicas',0)<1:
            raise SetupError(f'CSI controller {name} has no available replica. Repair the installation and collect fresh evidence.')
    if not console and deployments.get('aws-load-balancer-controller',{}).get('status',{}).get('availableReplicas',0)<1:
        raise SetupError('AWS Load Balancer Controller must be available for Kafka NLBs.')
    ready=[x for x in names('nodes').values() if any(c.get('type')=='Ready' and c.get('status')=='True' for c in x.get('status',{}).get('conditions',[]))]
    if not ready: raise SetupError('No Ready nodes in the evidence.')
    return {'readyNodes':len(ready),'drivers':sorted(drivers),'capacity':'user confirmation required','connectivity':'not tested'}


def scheduling(raw):
    import yaml
    try: value=yaml.safe_load(raw)
    except yaml.YAMLError: raise SetupError('Invalid scheduling YAML/JSON.') from None
    if not isinstance(value,dict) or set(value)-{'affinity','tolerations'}: raise SetupError('Only nodeAffinity and tolerations are supported.')
    current=value
    for key,allowed in [('affinity',{'nodeAffinity'}),('nodeAffinity',{'requiredDuringSchedulingIgnoredDuringExecution'}),('requiredDuringSchedulingIgnoredDuringExecution',{'nodeSelectorTerms'})]:
        current=current.get(key,{})
        if not isinstance(current,dict) or set(current)-allowed: raise SetupError('Unsupported scheduling affinity.')
    terms=current.get('nodeSelectorTerms',[])
    if not isinstance(terms,list) or len(terms)>1: raise SetupError('At most one nodeSelectorTerm is supported.')
    for term in terms:
        if not isinstance(term,dict) or set(term)!={'matchExpressions'} or not term['matchExpressions']: raise SetupError('Provide matchExpressions.')
        for exp in term['matchExpressions']:
            if not isinstance(exp,dict) or set(exp)!={'key','operator','values'} or exp['operator']!='In' or not isinstance(exp['key'],str) or not exp['key'] or not isinstance(exp['values'],list) or not exp['values'] or any(not isinstance(v,str) or not v for v in exp['values']):
                raise SetupError('Expressions require key, operator In and non-empty string values.')
    if not isinstance(value.get('tolerations',[]),list): raise SetupError('Tolerations must be a list.')
    return json.dumps(value)


def trust(state,cluster,namespace,sa,method):
    if method=='pod':
        statement={'Effect':'Allow','Principal':{'Service':'pods.eks.amazonaws.com'},'Action':['sts:AssumeRole','sts:TagSession'],
                   'Condition':{'StringEquals':{'aws:RequestTag/kubernetes-namespace':namespace,'aws:RequestTag/kubernetes-service-account':sa}}}
    else:
        issuer=cluster['identity']['oidc']['issuer'].removeprefix('https://')
        statement={'Effect':'Allow','Principal':{'Federated':f'arn:aws:iam::{state["account"]}:oidc-provider/{issuer}'},'Action':'sts:AssumeRoleWithWebIdentity',
                   'Condition':{'StringEquals':{issuer+':aud':'sts.amazonaws.com',issuer+':sub':f'system:serviceaccount:{namespace}:{sa}'}}}
    return {'Version':'2012-10-17','Statement':[statement]}


def role_preparation(directory,state,purpose,trust_policy):
    name=f'automq-setup-{state["name"]}-{purpose}'
    write_private(directory/f'{purpose}-trust.json',trust_policy)
    return script(directory,f'prepare-{purpose}.sh',[
        aws_command(state['home']['region'],'iam','create-role','--role-name',name,'--assume-role-policy-document',f'file://{purpose}-trust.json','--tags',json.dumps(tags(state['name'],purpose))),
        aws_command(state['home']['region'],'iam','wait','role-exists','--role-name',name)])


def binding_commands(directory,state,cluster,namespace,sa,method,role,purpose,existing=None):
    lines=[aws_command(state['home']['region'],'eks','update-kubeconfig','--name',cluster['name'],'--alias',cluster['arn'])]
    for resource,name,ns in [('namespace',namespace,[]),('serviceaccount',sa,['-n',namespace])]:
        get=kubectl(cluster,*ns,'get',resource,name,'--ignore-not-found','-o','name')
        lines += [f'SETUP_EXISTING=$({get})',f'[ -n "$SETUP_EXISTING" ] || {kubectl(cluster,*ns,"create",resource,name)}']
    if method=='pod':
        if not existing: lines.append(aws_command(state['home']['region'],'eks','create-pod-identity-association','--cluster-name',cluster['name'],'--namespace',namespace,'--service-account',sa,'--role-arn',role['Arn']))
    else:
        query=kubectl(cluster,'-n',namespace,'get','serviceaccount',sa,'-o','jsonpath={.metadata.annotations.eks\\.amazonaws\\.com/role-arn}')
        annotate=kubectl(cluster,'-n',namespace,'annotate','serviceaccount',sa,'eks.amazonaws.com/role-arn='+role['Arn'])
        lines += [f'SETUP_BOUND_ROLE=$({query})',
                  'if [ -z "$SETUP_BOUND_ROLE" ]; then '+annotate,
                  'elif [ "$SETUP_BOUND_ROLE" != '+shlex.quote(role['Arn'])+' ]; then echo "Conflicting ServiceAccount Role; stop without overwrite." >&2; exit 1; fi']
    return script(directory,f'bind-{purpose}.sh',lines)


def nodegroup_command(directory,state):
    name=f'automq-setup-{state["name"]}-nodes'; region=state['home']['region']; role=name+'-role'
    write_private(directory/'nodegroup-trust.json',{'Version':'2012-10-17','Statement':[{'Effect':'Allow','Principal':{'Service':'ec2.amazonaws.com'},'Action':'sts:AssumeRole'}]})
    lines=[aws_command(region,'iam','create-role','--role-name',role,'--assume-role-policy-document','file://nodegroup-trust.json','--tags',json.dumps(tags(state['name'],'nodegroup')))]
    for policy in ['AmazonEKSWorkerNodePolicy','AmazonEC2ContainerRegistryPullOnly','AmazonEKS_CNI_Policy']:
        lines.append(aws_command(region,'iam','attach-role-policy','--role-name',role,'--policy-arn','arn:aws:iam::aws:policy/'+policy))
    lines.append(aws_command(region,'iam','wait','role-exists','--role-name',role))
    count=state['node_count']+1
    lines.append(aws_command(region,'eks','create-nodegroup','--cluster-name',state['eks']['name'],'--nodegroup-name',name,'--node-role',f'arn:aws:iam::{state["account"]}:role/{role}',
        '--subnets',*[s['SubnetId'] for s in state['subnets']], '--instance-types',state['instance_type'],
        '--ami-type','AL2023_ARM_64_STANDARD' if state['instance_spec']['architecture']=='arm' else 'AL2023_x86_64_STANDARD',
        '--scaling-config',f'minSize={count},maxSize={count},desiredSize={count}', '--labels',json.dumps({'automq-deployment':state['name'],'node-type':'automq'}),
        '--taints','key=dedicated,value=automq,effect=NO_SCHEDULE',
        '--tags',json.dumps({x['Key']:x['Value'] for x in tags(state['name'],'nodegroup')})))
    lines.append(aws_command(region,'eks','wait','nodegroup-active','--cluster-name',state['eks']['name'],'--nodegroup-name',name))
    return script(directory,'prepare-nodegroup.sh',lines)


def component_commands(directory,state,cluster,data,purpose,console=False):
    """Prepare absent standard EKS components; never replace existing installations."""
    from pathlib import Path
    region=state['home']['region']; cluster_name=cluster['name']
    def names(key): return {x['metadata']['name'] for x in data.get(key,{}).get('items',[])}
    drivers=names('drivers'); deployments=names('deployments')
    lines=[aws_command(region,'eks','update-kubeconfig','--name',cluster_name,'--alias',cluster['arn'])]
    components=[]
    if 'ebs.csi.aws.com' not in drivers: components.append(('ebs-csi-controller-sa','aws-ebs-csi-driver','AmazonEBSCSIDriverPolicy'))
    if state['wal']=='FSWAL' and not console and 'efs.csi.aws.com' not in drivers: components.append(('efs-csi-controller-sa','aws-efs-csi-driver','AmazonEFSCSIDriverPolicy'))
    if components or (not console and 'aws-load-balancer-controller' not in deployments):
        lines.append(shlex.join(['eksctl','utils','associate-iam-oidc-provider','--cluster',cluster_name,'--region',region,'--approve']))
    for sa,addon,policy in components:
        role=f'automq-setup-{state["name"]}-{addon}'
        lines.append(shlex.join(['eksctl','create','iamserviceaccount','--cluster',cluster_name,'--region',region,'--namespace','kube-system','--name',sa,
                                '--role-name',role,'--attach-policy-arn','arn:aws:iam::aws:policy/service-role/'+policy,'--role-only','--approve']))
        lines.append(aws_command(region,'eks','create-addon','--cluster-name',cluster_name,'--addon-name',addon,'--service-account-role-arn',f'arn:aws:iam::{state["account"]}:role/{role}'))
        lines.append(aws_command(region,'eks','wait','addon-active','--cluster-name',cluster_name,'--addon-name',addon))
    if not console and 'aws-load-balancer-controller' not in deployments:
        policy_name=f'automq-setup-{state["name"]}-lbc'
        write_private(directory/'lbc-policy.json',(Path(__file__).parent/'lbc-policy-v2.10.0.json').read_text())
        lines.append('SETUP_LBC_POLICY=$('+aws_command(region,'iam','create-policy','--policy-name',policy_name,'--policy-document','file://lbc-policy.json',
            '--tags',json.dumps(tags(state['name'],'lbc')),'--query','Policy.Arn','--output','text')+')')
        lines.append(shlex.join(['eksctl','create','iamserviceaccount','--cluster',cluster_name,'--region',region,'--namespace','kube-system','--name','aws-load-balancer-controller',
            '--role-name',policy_name+'-role','--approve'])+' --attach-policy-arn "$SETUP_LBC_POLICY"')
        values={'clusterName':cluster_name,'region':region,'vpcId':state['vpc']['VpcId'],'serviceAccount':{'create':False,'name':'aws-load-balancer-controller'}}
        write_private(directory/'lbc-values.json',values)
        lines.append(shlex.join(['helm','--kube-context',cluster['arn'],'install','aws-load-balancer-controller','aws-load-balancer-controller',
            '--repo','https://aws.github.io/eks-charts','--version','1.10.0','--namespace','kube-system','--values','lbc-values.json','--wait','--timeout','10m']))
    return script(directory,f'prepare-{purpose}-components.sh',lines)


def validate_karpenter(pool,data,state):
    spec=pool.get('spec',{}).get('template',{}).get('spec',{})
    for requirement in spec.get('requirements',[]):
        expected={'node.kubernetes.io/instance-type':{state['instance_type']},'topology.kubernetes.io/zone':{s['AvailabilityZone'] for s in state['subnets']}}
        required=expected.get(requirement.get('key'))
        if required is None: continue
        values=set(requirement.get('values',[])); op=requirement.get('operator')
        if op=='In' and not required<=values or op=='NotIn' and required&values:
            raise SetupError('Karpenter NodePool excludes the selected machine or AZs.')
    reference=spec.get('nodeClassRef',{}).get('name')
    nodeclass=next((x for x in data.get('nodeclasses',{}).get('items',[]) if x['metadata']['name']==reference),None)
    if not nodeclass: raise SetupError('Evidence must include the selected NodePool EC2NodeClass.')
    actual={x['id'] for x in nodeclass.get('status',{}).get('subnets',[])}
    if not {x['SubnetId'] for x in state['subnets']}<=actual:
        raise SetupError('EC2NodeClass resolved subnets do not include the selected compute subnets.')
    limits=pool.get('spec',{}).get('limits',{})
    cpu=limits.get('cpu')
    if cpu is not None:
        try: capacity=float(str(cpu).removesuffix('m'))/(1000 if str(cpu).endswith('m') else 1)
        except ValueError: raise SetupError('Cannot parse Karpenter CPU limit.') from None
        if capacity<state['instance_spec']['cpu']*state['node_count']: raise SetupError('Karpenter CPU limit is smaller than requested node capacity.')
