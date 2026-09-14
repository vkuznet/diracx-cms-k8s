# helm deployment

```
# to install diracx-cms helm chart please use the following command:
helm install diracx-cms ./helm/diracx-cms -f ./helm/values-localhost.yaml --namespace diracx-cms --create-namespace --wait

# to use k8s cluster certificates instead of self generated one use the following command
#
# - if using a Root CA: pass the Root CA CRT file and private KEY file directly.
#
# - if using an Intermediate CA: concatenate your Intermediate CA certificate and
# the Root CA certificate into a single file before passing it to --set-file
# (Intermediate CA certificate first, Root CA certificate second).
#
helm install diracx-cms ./helm/diracx-cms \
  -f ./helm/values-localhost.yaml \
  --namespace diracx-cms --create-namespace \
  --set certManager.createSelfSignedCa=false \
  --set certManager.enabled=false \
  --set-file certManager.tlsCert=/path/to/ca-chain.crt \
  --set-file certManager.tlsKey=/path/to/ca.key \
  --wait

# to uninstall helm chart you may use
helm uninstall diracx-cms -n diracx-cms

# to list existing helm chart
helm list -n diracx-cms
```

For more information please read helm/diracx-cms/README.md file

