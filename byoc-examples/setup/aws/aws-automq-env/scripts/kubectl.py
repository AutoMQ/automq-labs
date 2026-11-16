#!/usr/bin/env python3
"""Use only the foundation cluster and current AWS profile; never current-context."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def main():
    result = subprocess.check_output(["terraform", f"-chdir={ROOT / 'infrastructure'}", "output", "-json"])
    infra = {k: v["value"] for k, v in json.loads(result).items()}
    config = {
        "apiVersion": "v1", "kind": "Config", "current-context": "example",
        "clusters": [{"name": "example", "cluster": {"server": infra["cluster_endpoint"], "certificate-authority-data": infra["cluster_certificate_authority_data"]}}],
        "contexts": [{"name": "example", "context": {"cluster": "example", "user": "deployer"}}],
        "users": [{"name": "deployer", "user": {"exec": {
            "apiVersion": "client.authentication.k8s.io/v1beta1", "command": "aws",
            "args": ["eks", "get-token", "--region", infra["region"], "--cluster-name", infra["cluster_name"]],
            "interactiveMode": "Never"}}}],
    }
    # This file has cluster metadata and an exec command, no tokens or AWS keys.
    with tempfile.TemporaryDirectory(prefix="automq-eks-kube-") as directory:
        path = Path(directory) / "config"
        path.write_text(json.dumps(config))
        path.chmod(0o600)
        return subprocess.call(["kubectl", "--kubeconfig", str(path), *sys.argv[1:]], env=os.environ)

if __name__ == "__main__":
    sys.exit(main())
