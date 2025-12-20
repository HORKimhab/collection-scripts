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

### Naming convention

- snake_case: e.g: `highlight_file`

### Ubuntu command

- remove alias: `unalias ${alias_name}`

### Test git on Window 

- Hello Universe from #HKimhab
- Hello Universe from Mac #HKimhab
