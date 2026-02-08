## Easy RSA 
wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.2.5/EasyRSA-3.2.5.tgz

dnf install -y openssl

tar xvf EasyRSA-3.2.5.tgz
cd EasyRSA-3.2.5/
./easyrsa init-pki
tree pki
# edit in pki/vars.example in privaete certificates
set_var EASYRSA_REQ_COUNTRY    "EG"
set_var EASYRSA_REQ_PROVINCE   "Cairo"
set_var EASYRSA_REQ_CITY       "Cairo"
set_var EASYRSA_REQ_ORG        "Link Development"
set_var EASYRSA_REQ_EMAIL      "ahmed.abdelsamad@linkdev.com"

set_var EASYRSA_CERT_EXPIRE    365

mv pki/vars.example pki/vars

#################################
./easyrsa build-ca
# New CA Key Passphrase:  *********
# Re-Enter New CA Key Passphrase:  *********
# Common Name (eg: your user, host, or server name) [Easy-RSA CA]:  root-ca
# CA creation complete and you may now import your CA into other services.


## generrate issue server certificate fro eaxmple httd
dnf install -y mod_ssl httpd openssl
mkdir new-csr
cd new-csr
openssl genrsa -out web-server.key 2048
openssl req -new -key web-server.key -out web-server.csr
# Country Name (2 letter code) [XX]: EG
# State or Province Name (full name) []: Cairo
# Locality Name (eg, city) [Default City]: Cairo
# Organization Name (eg, company) [Default Company Ltd]: Link Development
# Organizational Unit Name (eg, section) []: IT
# Common Name (eg, your name or your server's hostname) []: www.web-server.linkdev.net   ### important
# Email Address []:ahmed.abdelsamad@linkdev.com

# copy csr to ca root VM.
# from root-ca vm:
./easyrsa import-req /path/to/web-server.csr web-server
./easyrsa sign-req server web-server  ## server is template )server - client -...)
# Type the word 'yes' to continue, or any other input to abort.

# copy CA on all servers nodes
scp pki/ca.crt root@web-server:/etc/pki/ca-trust/source/anchors/
ssh root@web-server "update-ca-trust extract"
 

# /root/EasyRSA-3.2.5/pki/issued/web-server.crt
# copy web-server.crt to web-server VM  
# configure httpd to use ssl
cp web-server.crt /etc/pki/tls/certs/
cp web-server.key /etc/pki/tls/private/
vi /etc/httpd/conf.d/ssl.conf
# SSLCertificateFile /etc/pki/tls/certs/web-server.crt
# SSLCertificateKeyFile /etc/pki/tls/private/web-server.key
systemctl enable httpd --now
firewall-cmd --add-service=https --permanent
firewall-cmd --reload
# test from browser https://www.web-server.linkdev.com

## At Client VM
# copy ca.crt from root-ca VM to client VM
scp root@root-ca:/path/to/ca.crt /etc/pki/ca-trust/source/anchors/
ssh root@client "update-ca-trust extract"   
# test from client VM
curl -v https://www.web-server.linkdev.com
# * TLSv1.3 (OUT), TLS handshake, Client hello (1):
# * TLSv1.3 (IN), TLS handshake, Server hello (2):
# * TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
# * TLSv1.3 (IN), TLS handshake, Certificate (11):
# * TLSv1.3 (IN), TLS handshake, CERT verify (15):
# * TLSv1.3 (IN), TLS handshake, Finished (20):
# * TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
# * TLSv1.3 (OUT), TLS handshake, Finished (20):
# * SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
# * Server certificate:
# *  subject: C=EG; ST=Cairo; L=Cairo; O=Link Development; CN=www.web-server.linkdev.com
# *  start date: Jun  6 10:00:00 2024 GMT
# *  expire date: Jun  6 10:00:00 2025 GMT
# *  issuer: C=EG; ST=Cairo; L=Cairo; O=Link Development; CN=root-ca
# *  SSL certificate verify ok.
# > GET / HTTP/1.1      
# > Host: www.web-server.linkdev.com
# > User-Agent: curl/7.61.1
# > Accept: */*
# > < HTTP/1.1 200 OK
# < Date: Thu, 06 Jun 2024 10:30:00 GMT
# < Server: Apache/2.4.37 (CentOS)
# < Last-Modified: Thu, 06 Jun 2024 09:00:00 GMT
# < ETag: "2d-5c3b5e1b4f840"
# < Accept-Ranges: bytes
# < Content-Length: 45
# < Content-Type: text/html; charset=UTF-8
# < 
# < Hello, this is a secure web server! 
########################################################################
## Renew certificates
./easyrsa renew web-server

# Revoke certificates
./easyrsa revoke-renewed  web-server
# Type the word 'yes' to continue, or any other input to abort.
./easyrsa gen-crl

## httpd read new certifcate and invoke old one
## copy crl to web-server
scp pki/crl.pem root@web-server:/etc/pki/tls/crl.pem
vi /etc/httpd/conf.d/ssl.conf
# SSLCARevocationFile /etc/pki/tls/crl.pem
systemctl restart httpd

curl -v --crlft /etc/pki/tls/crl.pem  http://www.web-server.linkdev.com/
# * TLSv1.3 (OUT), TLS handshake, Client hello (1):
# * TLSv1.3 (IN), TLS alert, Alert (2):
# * SSL certificate problem: certificate has been revoked    
########################################################################   
