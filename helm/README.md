# helm deployment

```
# to install diracx-cms helm chart please use the following command:
helm install diracx-cms ./helm/diracx-cms -f ./helm/values-localhost.yaml --namespace diracx-cms --create-namespace --wait

# to use k8s cluster certificates instead of self generated one use the following command
# - if using a Root CA: pass the Root CA CRT file and private KEY file
# - if using an Intermediate CA: pass the chained CRT file and private KEY file
#
helm install diracx-cms ./helm/diracx-cms \
  -f ./helm/values-localhost.yaml \
  --namespace diracx-cms --create-namespace \
  --set certManager.createSelfSignedCa=false \
  --set-file certManager.tlsCert=/path/to/ca-chain.crt \
  --set-file certManager.tlsKey=/path/to/ca.key \
  --wait

# to uninstall helm chart you may use
helm uninstall diracx-cms -n diracx-cms

# to list existing helm chart
helm list -n diracx-cms
```

For more information please read helm/diracx-cms/README.md file

---

### How to create ca-chain.crt
On our k8s clusters we use config.testXX area which contains encrypted
certificates for XX cluster. You can obtain them from
[services_config](https://gitlab.cern.ch/cmsweb-k8s/services_config/-/tree/test/config.test18/auth-proxy-server)
repository. To decrypt specific config.testXX files please use the following command:

```
# clone CMSKubernetes repository and visit CMSKubernetes/kubernetes/scripts area
# from there you may decrypt files you like, e.g.
./decrypt-secrets.sh auth /path/services_config/config.test18/auth-proxy-server/tls.crt.encrypted
```

Then, we can chain crt files and verify their correctness
```
# copy your desired set of certificates files locally, e.g.
mkdir certs
cp /path/services_config/config.test18/auth-proxy-server/{tls.key,tls.crt,CERN_CA.crt} certs
# create chained pem file
cat certs/tls.crt certs/CERN_CA.crt > certs/ca-chain.pem
# verify chain certificate
openssl crl2pkcs7 -nocrl -certfile ./certs/ca-chain.pem | openssl pkcs7 -print_certs -text | grep -E "Subject:|Issuer:"
        Issuer: DC=ch, DC=cern, CN=CERN Certification Authority
        Subject: CN=cmsweb-test18.cern.ch
        Issuer: C=ch, O=CERN, CN=CERN Root Certification Authority 2
        Subject: DC=ch, DC=cern, CN=CERN Certification Authority
```
Here, you should see that the output displays exactly two certificates where
the 1st Issuer matches the 2nd Subject.
