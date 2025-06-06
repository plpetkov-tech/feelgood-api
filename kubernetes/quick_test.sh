POD_IP=10.42.5.7:8000
for i in {1..99}; do curl $POD_IP/$i; done
for i in {1..99}; do curl $POD_IP/$i; done
for i in {1..99}; do curl $POD_IP/security; done
for i in {1..99}; do curl $POD_IP/security/vex ; done
for i in {1..99}; do curl $POD_IP/security/sbom ; done
for i in {1..99}; do curl $POD_IP/security/provenance ; done
for i in {1..99}; do curl $POD_IP/security/provenance ; done
for i in {1..99}; do curl $POD_IP/security/provenance ; done
for i in {1..99}; do curl $POD_IP/docs ; done
for i in {1..99}; do curl $POD_IP/docs/oauth2-redirect ; done
