### На зарубежном хосте

1. Установить Docker и склонить директорию
```
apt update && apt install docker.io
git clone https://github.com/worthdone/alttab
```

1. Собрать образ
```
docker build -t telemt:local . --build-arg TARGETARCH=amd64 --target minimal
```

2. Сгенерировать секрет:
```
cat /dev/urandom | tr -dc '0-9a-f' | head -c 32; echo
```

3. Поменять `tls_domain` и пароль пользователя (самая последняя строчка) в `config.toml`.

4. Запустить прокси
```
docker run -d --restart unless-stopped --name telemt   -p 8443:443   -e RUST_LOG=info   -v "$PWD/config.toml:/app/config.toml:ro"    --cap-drop ALL --cap-add NET_BIND_SERVICE   --ulimit nofile=65536:65536 telemt:local /telemt /app/config.toml
```

5. Посмотреть на ссылку для подключения, дальше в нее нужно подставить требуемый IP/домен
```
docker logs -f telemt | fgrep tg
```
