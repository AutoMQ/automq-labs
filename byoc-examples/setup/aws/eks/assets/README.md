# Architecture diagram source

`deployment-architecture.py` generates the adjacent PNG with [diagrams](https://github.com/mingrammer/diagrams) 0.25.1 and Graphviz (`neato`). Install those dependencies in a Python virtual environment, then run:

```bash
python deployment-architecture.py
```

The image is written beside the source regardless of the current directory. Fixed positions and transparent boundary panels keep the three AZs aligned at a readable Markdown width. AWS and Kubernetes service images come from the diagrams node catalog; boundary panels are layout primitives.

The overview shows the default customer deployment, not every Kubernetes component. Solid blue edges show Kafka/data traffic, and the dashed purple edge shows Console's IAM role and EKS Access Entry management path. S3 traffic uses the existing S3 Gateway Endpoint, omitted from the overview. The Console, each Instance and AWS-integrated controllers use separate IRSA roles; the diagram is not evidence of IAM permissions. Managed node groups and Cluster Autoscaler provide EC2 capacity; other cluster add-ons and the LB Controller are omitted for clarity.
