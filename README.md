Certs files for local dev are ends up in 2025
If certs are expired, you can generate new ones with:
```mkcert -cert-file certs/local-cert.pem -key-file certs/local-key.pem "*.local.barlito.fr"```
