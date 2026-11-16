#!/usr/bin/env python3
"""Render the actual pinned official Chart without contacting Kubernetes."""
import json
import re
from pathlib import Path
import subprocess
import sys
import tempfile
import yaml


def main():
    with tempfile.TemporaryDirectory(prefix="automq-chart-check-") as directory:
        if len(sys.argv) > 1:
            chart = sys.argv[1]
        else:
            subprocess.run(["helm", "pull", "oci://automq.azurecr.io/helm/automq-byoc-console-chart", "--version", "8.3.28", "--destination", directory], check=True)
            chart = str(Path(directory) / "automq-byoc-console-chart-8.3.28.tgz")
        values = {
            "fullnameOverride": "automq-console", "cloudProvider": "aws",
            "image": {"repository": "registry.example.test/console", "tag": "compatible-test"},
            "serviceAccount": {"name": "automq-console"},
            "automqByocConsole": {"config": {"existingSecret": "automq-console-config"}},
            "aws": {"account": "123456789012", "network": {"vpcId": "vpc-example", "subnetIds": ["subnet-a", "subnet-b", "subnet-c"]}},
            "nodeAffinities": [{"key": "automq.io/pool", "values": ["system"]}],
            "persistence": {"storageClass": "automq-console-gp3", "size": "20Gi"},
            "service": {"type": "ClusterIP"}, "ingress": {"enabled": False},
        }
        path = Path(directory) / "values.json"
        path.write_text(json.dumps(values))
        output = subprocess.check_output(["helm", "template", "automq-console", chart, "--namespace", "automq-console", "--values", str(path)])
        docs = {d["kind"]: d for d in yaml.safe_load_all(output) if d}
        assert "ServiceAccount" not in docs and "Secret" not in docs and "Ingress" not in docs
        pod = docs["StatefulSet"]["spec"]["template"]["spec"]
        assert pod["serviceAccountName"] == "automq-console"
        container = pod["containers"][0]
        assert container["image"] == "registry.example.test/console:compatible-test"
        env = {x["name"]: x.get("value") for x in container["env"]}
        assert env["DEPLOY_TYPE"] == "K8S" and env["VPC"] == "vpc-example" and env["SCOPE"] == "123456789012"
        secret = next(x for x in container["env"] if x["name"] == "CONFIG")["valueFrom"]["secretKeyRef"]
        assert secret == {"name": "automq-console-config", "key": "config"}
        assert pod["volumes"][0]["persistentVolumeClaim"]["claimName"] == "automq-console"
        assert pod["affinity"]["nodeAffinity"]["requiredDuringSchedulingIgnoredDuringExecution"]["nodeSelectorTerms"][0]["matchExpressions"][0] == {"key": "automq.io/pool", "operator": "In", "values": ["system"]}
        assert docs["PersistentVolumeClaim"]["spec"]["storageClassName"] == "automq-console-gp3"
        assert docs["Service"]["spec"]["type"] == "ClusterIP"
        # Verify the public command/output contract against the actual Chart name,
        # rather than assuming its Service uses the StatefulSet/PVC fullname.
        root = Path(__file__).resolve().parents[1]
        outputs = (root / "console" / "outputs.tf").read_text()
        expected_service = re.search(r'output "service_name" \{\s*value\s*=\s*"([^"\n]+)"', outputs).group(1)
        assert docs["Service"]["metadata"]["name"] == expected_service
        target = f"service/{expected_service} 8080:80"
        assert target in outputs, "Terraform port-forward output must target the rendered Service."
        readme = (root / "README.md").read_text()
        assert target in readme, "README port-forward must target the rendered Service."
        assert f"`{expected_service}` ClusterIP service" in readme, "ALB backend must target the rendered Service."
        print("PASS: official 8.3.28 Chart renders external KSA/Secret, gp3 PVC, system scheduling and ClusterIP.")

if __name__ == "__main__":
    main()
