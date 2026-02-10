# collection scripts

## Install

```bash
curl -o ~/.custom-bash.sh https://raw.githubusercontent.com/HORKimhab/collection-scripts/main/.custom-bash.sh
```

```bash
# Append .custom-bash.sh to .bashrc
echo -e "\n# ----------------------------- Append or Customize ---------------------------------------------------\nif [ -f ~/.custom-bash.sh ]; then\n  . ~/.custom-bash.sh\nfi\n# ----------------------------- Append or Customize ---------------------------------------------------" >> ~/.bashrc
```

```bash
# Reload .bashrc
source .bashrc
```

## Install postman without third party or apt

```bash
curl -o ~/install-postman-without-third-party.sh \
    https://raw.githubusercontent.com/HORKimhab/collection-scripts/main/install-postman-without-third-party.sh
sudo chmod +x ~/install-postman-without-third-party.sh
```

```bash
# Run it
bash ~/install-postman-without-third-party.sh
```

## TODO

- Use fish and separate append alias to one file, use it with 'include'
- `sudo find "$dir" -type f -name "$basename.*bak" -mtime +0 -print0 | xargs -0 -r sudo rm` is slow...
- Install mysql via script: https://chatgpt.com/share/694617e7-6884-800b-bd3d-65997827355e

```bash
# Set auto
# Start ssh-agent if not running
  if [ -z "$SSH_AUTH_SOCK" ]; then
  eval "$(ssh-agent -s)" >/dev/null
  ssh-add /home/deploy/.ssh/rean-it-deploy >/dev/null 2>&1
  fi
```

### Naming convention

- snake_case: e.g: `highlight_file`

### Ubuntu command

- remove alias: `unalias ${alias_name}`

### Test git on Window

- Hello Universe from #HKimhab
- Hello Universe from Mac #HKimhab

### Secure-laravel-code

```bash
# Store encrypt laravel on dockerhub
# Mac
# brew install age

# Encrypt laravel archive
tar cz --exclude-vcs --exclude-from=.gitignore --exclude='._*' --no-xattrs . | age -p -o laravel.enc

# Decrypt
age -d -p -o - laravel.enc | tar xz

# Run laravel inside docker
docker build -t template-secure-laravel-code . && docker run -p 8000:8000 -it template-secure-laravel-code sh

# Docker push
tar cz --exclude-vcs --exclude-from=.gitignore --exclude='._*' . | age -p -o laravel.enc && docker build -t 460616120572/template-secure-laravel-code .

docker push 460616120572/template-secure-laravel-code:latest

# Docker pull and run it
# Key check in "General doc"
docker pull 460616120572/template-secure-laravel-code:latest && docker build -t 460616120572/template-secure-laravel-code . && docker run -p 8000:8000 -it 460616120572/template-secure-laravel-code sh

```
