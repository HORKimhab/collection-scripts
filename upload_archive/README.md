# Archive.org upload

`upload_archive.py` uploads one file to an Archive.org item using IAS3 credentials from env, with optional pre-upload OpenSSL encryption.

Install dependencies:

```bash
python3 -m pip install -r upload_archive/requirements.txt
```

Prepare credentials:

```bash
cp upload_archive/.archive.env.example upload_archive/.archive.env
```

Plain upload:

```bash
python3 upload_archive/upload_archive.py \
  --identifier my-item-2026 \
  --file ./backup.tar.gz \
  --title "My Backup" \
  --mediatype data \
  --collection opensource
```

Encrypted upload:

```bash
export ARCHIVE_PASSWORD='change-me'

python3 upload_archive/upload_archive.py \
  --identifier my-item-2026 \
  --file ./backup.tar.gz \
  --title "My Backup" \
  --mediatype data \
  --collection opensource \
  --password-env ARCHIVE_PASSWORD
```

OpenSSL settings used for encrypted uploads:

```bash
openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt
```
