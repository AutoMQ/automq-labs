"""Portable EKS Console Helm bundle with persistent storage and secret credentials."""
import os
import shutil
from core import TEMPLATES, write_private, aws_command, tags
from resources import script
from eks import kubectl


def generate_eks_console(directory,state):
    cluster=state['console_eks']; name='automq-console'; storage=f'automq-setup-{state["name"]}-console-gp3'
    chart=directory/'console-chart'
    if chart.exists(): shutil.rmtree(chart)
    shutil.copytree(TEMPLATES/'automq-byoc-console-chart',chart)
    for root,dirs,files in os.walk(chart):
        os.chmod(root,0o700)
        for file in files: os.chmod(os.path.join(root,file),0o600)
    secret={'apiVersion':'v1','kind':'Secret','metadata':{'name':name+'-config','namespace':name},'type':'Opaque',
            'stringData':{'config':state['home']['config'],'password':state['console_password'],**state['api_credentials']}}
    write_private(directory/'console-secret.json',secret)
    params={'type':'gp3','encrypted':'true'}
    for i,tag in enumerate(tags(state['name'],'console-data'),1): params[f'tagSpecification_{i}']=tag['Key']+'='+tag['Value']
    sc={'apiVersion':'storage.k8s.io/v1','kind':'StorageClass','metadata':{'name':storage,'labels':{'app.kubernetes.io/part-of':'automq','app.kubernetes.io/managed-by':'automq-setup'}},
        'provisioner':'ebs.csi.aws.com','parameters':params,'reclaimPolicy':'Retain','volumeBindingMode':'WaitForFirstConsumer','allowVolumeExpansion':True}
    write_private(directory/'console-storageclass.json',sc)
    repository,tag=state['home']['image'].rsplit(':',1)
    values={'fullnameOverride':name,'automqByocConsole':{'config':{'existingSecret':name+'-config'}},'cloudProvider':'aws',
        'aws':{'account':state['account'],'network':{'vpcId':state['vpc']['VpcId'],'subnetIds':[x['SubnetId'] for x in state.get('console_eks_subnets',state.get('subnets',[state['subnet']]))]}},
        'nodeAffinities':[{'key':'topology.kubernetes.io/zone','values':sorted({x['AvailabilityZone'] for x in state.get('console_eks_subnets',state.get('subnets',[state['subnet']]))})}],
        'image':{'repository':repository,'tag':tag},'serviceAccount':{'name':name},
        'persistence':{'storageClass':storage,'accessModes':['ReadWriteOnce'],'size':'20Gi'},
        'service':{'type':'ClusterIP','ports':{'web':80}},'ingress':{'enabled':False}}
    write_private(directory/'console-values.json',values)
    import shlex
    helm=shlex.join(['helm','--kube-context',cluster['arn']])
    lines=[aws_command(state['home']['region'],'eks','update-kubeconfig','--name',cluster['name'],'--alias',cluster['arn']),
        kubectl(cluster,'get','csidriver','ebs.csi.aws.com'),
        kubectl(cluster,'-n',name,'get','serviceaccount',name),
        kubectl(cluster,'create','-f','console-storageclass.json'),kubectl(cluster,'create','-f','console-secret.json'),
        helm+' template automq-console ./console-chart --namespace automq-console --values console-values.json > console-rendered.yaml',
        helm+' install automq-console ./console-chart --namespace automq-console --values console-values.json --wait --timeout 10m',
        kubectl(cluster,'-n',name,'rollout','status','statefulset/'+name,'--timeout=600s'),
        kubectl(cluster,'-n',name,'get','pvc,pods,service')]
    script(directory,'install-console-eks.sh',lines)
    script(directory,'access-console.sh',[kubectl(cluster,'-n',name,'port-forward','service/'+name+'-web-loadbalancer','8080:80','--address','127.0.0.1')])
    write_private(directory/'CONSOLE-INSTALL.md',f'''# EKS Console installation

Execute the generated identity binding and Policy commands first. Copy this private bundle to a machine with AWS CLI, kubectl and Helm access to `{cluster['name']}`. Run `bash install-console-eks.sh`, then `bash access-console.sh`; browse http://127.0.0.1:8080 on that machine. Keep port-forward running.

First installation uses create/install and stops on collisions; it never overwrites an existing workload, StorageClass or Secret. Verify PVC Bound, Pod Ready and data mounted at /data. This bundle pins the bundled Chart separately from the Home image.

The EBS StorageClass uses Retain. For recovery, identify the original PV, EBS volume and stopped workload before changing anything; rebind the original retained PV to the original PVC instead of creating an empty replacement. This guide does not automatically delete or recover volumes. Preserve backups separately.

Wait for Home ACTIVE and an available UsageBased subscription/trial before executing the cluster creation curl. These files contain credentials and must remain private.
''')
