#!/usr/bin/env bash

kind delete cluster --name mlflow

kind create cluster --name mlflow --config kind/kind-config.yaml