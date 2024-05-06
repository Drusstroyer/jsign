#!/bin/sh
#
# Script generating a certificate chain
#

rm -f jsign-* keystore*

# Create the file defining the x509 extensions
cat > extensions.cnf <<- "EOF"
[ root ]
basicConstraints = CA:TRUE
keyUsage = keyCertSign,cRLSign
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer

[ intermediate ]
basicConstraints = CA:TRUE,pathlen:0
keyUsage = keyCertSign,cRLSign
extendedKeyUsage = codeSigning
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
crlDistributionPoints=URI:http://localhost:31457/jsign-ca.crl
authorityInfoAccess = caIssuers;URI:http://localhost:31457/jsign-ca.cer
authorityInfoAccess = OCSP;URI:http://localhost:31457/ocsp

[ final ]
basicConstraints = CA:FALSE
keyUsage = digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
crlDistributionPoints=URI:http://localhost:31457/jsign-intermediate.crl
authorityInfoAccess = caIssuers;URI:http://localhost:31457/jsign-intermediate.cer
authorityInfoAccess = OCSP;URI:http://localhost:31457/ocsp
EOF

CERT_OPTS="-days 7300 -text -sha256"
YEAR=$(date +'%Y')

# Generate the root certificate
openssl req -new -newkey rsa:4096 -nodes -keyout jsign-root-ca.key -x509 -extensions v3_ca -subj "/CN=Jsign Root Certificate Authority $YEAR" -out jsign-root-ca.pem $CERT_OPTS

# Generate the intermediate certificate
openssl req -new -newkey rsa:2048 -nodes -keyout jsign-code-signing-ca.key -subj "/CN=Jsign Code Signing CA $YEAR" -out jsign-code-signing-ca.csr
openssl x509 -req -in jsign-code-signing-ca.csr -CA jsign-root-ca.pem -CAkey jsign-root-ca.key -CAcreateserial \
             -out jsign-code-signing-ca.pem $CERT_OPTS -extfile extensions.cnf -extensions intermediate

# Generate the test certificates (reusing the existing keys)
openssl req -new -key privatekey.pkcs1.pem -subj "/CN=Jsign Code Signing Test Certificate $YEAR (RSA)" -out jsign-test-certificate.csr
openssl x509 -req -in jsign-test-certificate.csr -CA jsign-code-signing-ca.pem -CAkey jsign-code-signing-ca.key -CAcreateserial \
             -out jsign-test-certificate.pem $CERT_OPTS -extfile extensions.cnf -extensions final

openssl req -new -key privatekey-ec-p384.pkcs1.pem -subj "/CN=Jsign Code Signing Test Certificate $YEAR (EC)" -out jsign-test-certificate-ec.csr
openssl x509 -req -in jsign-test-certificate-ec.csr -CA jsign-code-signing-ca.pem -CAkey jsign-code-signing-ca.key -CAcreateserial \
             -out jsign-test-certificate-ec.pem $CERT_OPTS -extfile extensions.cnf -extensions final

# Generate the certificate chains
cat jsign-root-ca.pem jsign-code-signing-ca.pem jsign-test-certificate.pem > jsign-test-certificate-full-chain-reversed.pem
cat jsign-test-certificate.pem jsign-code-signing-ca.pem jsign-root-ca.pem > jsign-test-certificate-full-chain.pem
cat jsign-root-ca.pem jsign-code-signing-ca.pem > jsign-test-certificate-partial-chain-reversed.pem
cat jsign-code-signing-ca.pem jsign-root-ca.pem > jsign-test-certificate-partial-chain.pem

# Generate the SPC files (DER encoded certificate chains)
openssl crl2pkcs7 -nocrl -certfile jsign-test-certificate-full-chain.pem          -outform DER -out jsign-test-certificate-full-chain.spc
openssl crl2pkcs7 -nocrl -certfile jsign-test-certificate-full-chain-reversed.pem -outform DER -out jsign-test-certificate-full-chain-reversed.spc

# Generate the PKCS#12 keystores
OPENSSL_OPTS="-export -inkey privatekey.pkcs1.pem -name test -passout pass:password"
openssl pkcs12 $OPENSSL_OPTS -in jsign-test-certificate-full-chain.pem -out keystore.p12
openssl pkcs12 $OPENSSL_OPTS -in jsign-test-certificate.pem            -out keystore-no-chain.p12

OPENSSL_OPTS="-export -inkey privatekey-ec-p384.pkcs1.pem -name test -passout pass:password"
openssl pkcs12 $OPENSSL_OPTS -in jsign-test-certificate-ec.pem         -out keystore-ec.p12

# Generate the Java keystores
KEYTOOL_OPTS="-importkeystore -srcstoretype pkcs12 -srcstorepass password -srcalias test -deststoretype jks -deststorepass password -destalias test"
keytool $KEYTOOL_OPTS -srckeystore keystore.p12          -destkeystore keystore.jks
keytool $KEYTOOL_OPTS -srckeystore keystore-no-chain.p12 -destkeystore keystore-no-chain.jks

KEYTOOL_OPTS="-importkeystore -srcstoretype pkcs12 -srcstorepass password -srcalias test -deststoretype jceks -deststorepass password -destalias test"
keytool $KEYTOOL_OPTS -srckeystore keystore.p12          -destkeystore keystore.jceks

# Generate the keystore with two entries
cp keystore.p12 keystore-two-entries.p12
keytool -importkeystore \
        -srcstoretype  pkcs12 -srcstorepass  password -srcalias  test  -srckeystore keystore.p12 \
        -deststoretype pkcs12 -deststorepass password -destalias test2 -destkeystore keystore-two-entries.p12

# Generate the empty keystore
cp keystore.p12 keystore-empty.p12
keytool -delete -alias test -storepass password -keystore keystore-empty.p12

# Cleanup
rm *.srl
rm jsign-root-ca.key
rm jsign-code-signing-ca.key
rm jsign-code-signing-ca.csr
rm jsign-test-certificate*.csr
rm extensions.cnf
