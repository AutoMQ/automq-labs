"""Render with diagrams==0.25.1 and Graphviz; PNG is written beside this file.

Fixed Graphviz positions keep the customer overview compact and reproducible.
Solid blue edges show Kafka/data traffic; the dashed purple edge is Kubernetes
management. S3 access uses the existing gateway endpoint (omitted for clarity).
Each workload uses its own IRSA role; the drawing does not prove IAM policy.
Cluster add-ons and the LB Controller are omitted for clarity.
Managed node-group capacity is supplied by Cluster Autoscaler.
"""
from pathlib import Path

from diagrams import Cluster, Diagram, Edge, getcluster
from diagrams.aws.compute import EKS
from diagrams.aws.network import NLB
from diagrams.aws.storage import S3
from diagrams.k8s.compute import Pod
from diagrams.onprem.client import Client

OUTPUT = Path(__file__).resolve().with_suffix("")
DATA, CONTROL = "#176B9B", "#76629D"


def icon(kind, label, x, y):
    return kind(label, pos=f"{x},{y}!", pin="true", width="1.1", height="2.2" if "\n" in label else "1.8")


with Diagram(
    "", filename=str(OUTPUT), show=False, outformat="png",
    graph_attr={"fontname": "Helvetica", "fontsize": "18", "pad": "0.3", "splines": "polyline", "bgcolor": "white", "dpi": "110", "overlap": "true"},
    node_attr={"fontname": "Helvetica", "fontsize": "17", "fontcolor": "#233448"},
    edge_attr={"fontname": "Helvetica", "fontsize": "12", "arrowsize": "0.7"},
) as diagram:
    diagram.dot.engine = "neato"
    client = icon(Client, "Kafka client", -2.2, 4.8)
    with Cluster("", graph_attr={"bgcolor": "#FFFFFF", "color": "#CAD4DF", "fontcolor": "#233448", "fontsize": "19", "margin": "16"}):
        # Neato preserves fixed node positions; explicit panels retain nested boundaries.
        # These are deployment boundaries, not service or provider icons.
        panels = [
            ("account-panel", "Your AWS account  |  One Region", 5.6, 2.15, 12.6, 9.1, "#FFFFFF", "#CAD4DF", "19"),
            ("vpc-panel", "Existing VPC  |  Private subnets", 4.75, 3.15, 10.3, 5.7, "#F7FAFD", "#9BB7CE", "17"),
            ("eks-panel", "", 4.75, 2.1, 10.0, 3.0, "#FFFFFF", "#769FC3", "17"),
            ("system-panel", "System pool", 1.0, 2.0, 1.95, 2.2, "#F3F0FA", "#C6BADC", "15"),
            ("az-a-panel", "AZ A", 3.5, 2.0, 1.95, 2.2, "#F1F8FC", "#ADD1E6", "15"),
            ("az-b-panel", "AZ B", 6.0, 2.0, 1.95, 2.2, "#F1F8FC", "#ADD1E6", "15"),
            ("az-c-panel", "AZ C", 8.5, 2.0, 1.95, 2.2, "#F1F8FC", "#ADD1E6", "15"),
        ]
        for key, label, x, y, width, height, fill, border, fontsize in panels:
            getcluster().node(key, label, pos=f"{x},{y}!", pin="true", shape="box", style="rounded", fillcolor=fill, color=border, width=str(width), height=str(height), fixedsize="true", labelloc="t", labeljust="l", fontsize=fontsize, fontcolor="#233448")
        getcluster().node("eks-heading", "EKS managed node groups", pos="1.9,3.4!", pin="true", shape="plaintext", width="3.7", height="0.35", fontsize="17", fontcolor="#233448")
        getcluster().node("access-caption", "IRSA role\nEKS Access Entry", pos="2.6,0.0!", pin="true", shape="plaintext", width="2.8", height="0.6", fontsize="14", fontcolor=CONTROL)
        with Cluster("Existing VPC  |  Private subnets", graph_attr={"bgcolor": "#F7FAFD", "color": "#9BB7CE", "fontsize": "17", "margin": "16"}):
            nlb = icon(NLB, "Internal NLB", 5.1, 4.8)
            with Cluster("New EKS worker nodes", graph_attr={"bgcolor": "#FFFFFF", "color": "#769FC3", "fontsize": "17", "margin": "16"}):
                with Cluster("System pool", graph_attr={"bgcolor": "#F3F0FA", "color": "#C6BADC", "fontsize": "15", "margin": "14"}):
                    console = icon(Pod, "AutoMQ Console", 1.0, 2.0)
                brokers = []
                for zone, x in [("AZ A", 3.5), ("AZ B", 6.0), ("AZ C", 8.5)]:
                    with Cluster(zone, graph_attr={"bgcolor": "#F1F8FC", "color": "#ADD1E6", "fontsize": "15", "margin": "14"}):
                        brokers.append(icon(Pod, "AutoMQ", x, 2.0))
        api = icon(EKS, "EKS control plane\nAWS-managed", 1.0, -0.9)
        data = icon(S3, "Data bucket\nKafka + S3WAL", 6.0, -0.7)
        ops = icon(S3, "Ops bucket", 11.1, -0.9)
    diagram.dot.node("capacity-caption", "Cluster Autoscaler adjusts EC2 capacity within managed node-group limits.", pos="5.0,-2.85!", pin="true", shape="plaintext", width="12.0", height="0.4", fontsize="14", fontcolor="#233448")
    client >> Edge(label="Private Kafka", color=DATA, penwidth="2.0") >> nlb
    nlb >> Edge(color=DATA, penwidth="2.0") >> brokers
    for broker in brokers:
        broker >> Edge(color=DATA, penwidth="1.6") >> data
    console >> Edge(color=CONTROL, style="dashed", penwidth="1.4") >> api
