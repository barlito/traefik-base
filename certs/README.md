# Certificats TLS locaux

`local-cert.pem` / `local-key.pem` : certificat **auto-signé** wildcard (`*.local.barlito.fr` + `local.barlito.fr`), monté par `traefik-dynamic.local.yml`.

- Usage **local uniquement**. La clé privée est volontairement versionnée : elle ne protège rien de sensible.
- Jamais utilisé en production (Let's Encrypt via `traefik.prod.yml`).
- Expiration : **2029-02-12**.
- Le navigateur affiche un avertissement tant que le certificat n'est pas approuvé.

## Régénérer

```bash
cd certs
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
  -keyout local-key.pem -out local-cert.pem -days 825 \
  -subj "/CN=*.local.barlito.fr" \
  -addext "subjectAltName=DNS:local.barlito.fr,DNS:*.local.barlito.fr" \
  -addext "basicConstraints=CA:FALSE" \
  -addext "keyUsage=digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=serverAuth"
```

Puis redéployer (`make deploy-local`).

## L'approuver localement (optionnel)

Importer `local-cert.pem` comme autorité dans le navigateur ou le système, par exemple sous Debian/Ubuntu :

```bash
sudo cp certs/local-cert.pem /usr/local/share/ca-certificates/traefik-local.crt
sudo update-ca-certificates
```

(Firefox/Chrome ont leur propre magasin : importer le fichier dans leurs paramètres.)

## Alternative : mkcert

Pour un certificat approuvé par le navigateur sans avertissement :

```bash
mkcert "*.local.barlito.fr" local.barlito.fr
```

Renommer les fichiers générés en `local-cert.pem` / `local-key.pem`.

La PR #16 (en cours) remplacera ce certificat par un vrai wildcard Let's Encrypt via DNS-01.
