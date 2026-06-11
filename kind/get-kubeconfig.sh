#!/usr/bin/env bash

kind get kubeconfig --name mlflow > ~/.kube/remote/mlflow.yaml
sleep 1
kubectx mlflow-kind-mlflow