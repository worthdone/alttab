# Telemt: прокси через два хоста

Схема подключения:

```text
Telegram → entry-хост в России:443 → exit-хост за пределами России:8443 → Telegram
```
Между entry- и exit-хостами используется обычный NAT без дополнительного шифрования.

## Требования

Инструкция протестирована на чистых установках Ubuntu Server 24.04 LTS. Все команды на обоих хостах необходимо выполнять от пользователя `root`.

Если вы подключились под обычным пользователем, сначала откройте root-сессию:

```sh
sudo -i
```

Команда `id -u` должна вывести `0`.

IP-адреса в инструкции:

- `ENTRY_IP` — публичный IPv4 российского entry-хоста. Он указывается в `--public-host` и попадает в ссылки Telegram.
- `EXIT_IP` — публичный IPv4 зарубежного exit-хоста. Он указывается в `--backend-ip` на entry-хосте.

Узнать публичный IPv4 текущего сервера:

```sh
curl -4 -fsS https://api.ipify.org; echo
```

Выполните эту команду отдельно на entry- и exit-хосте и сохраните оба адреса.

## 1. Exit-хост

На зарубежном сервере:

```sh
apt-get update && apt-get install -y git
git clone https://github.com/worthdone/alttab
cd alttab
./setup-exit.sh \
    --tls-domain example.com \
    --public-host 203.0.113.10
```

Замените `example.com` на домен для TLS-маскировки, а `203.0.113.10` — на публичный IP или домен российского entry-хоста. По умолчанию Telemt доступен на exit-хосте через порт `8443`.

Для другого backend-порта добавьте, например, `--backend-port 9443`.

## 2. Entry-хост

На российском сервере:

```sh
apt-get update && apt-get install -y git
git clone https://github.com/worthdone/alttab
cd alttab
./setup-entry.sh --backend-ip 206.189.74.192
```

Замените `206.189.74.192` на публичный IP exit-хоста. Если на exit-хосте выбран другой порт, передайте здесь тот же параметр:

```sh
./setup-entry.sh --backend-ip 206.189.74.192 --backend-port 9443
```

Входящий порт по умолчанию — `443`. Скрипт сохраняет весь активный набор правил через `netfilter-persistent`.

## Ссылки Telegram

После настройки exit-хоста сгенерируйте обе полные ссылки напрямую из конфигурации:

```sh
./generate-links.sh
```

Другой путь к конфигурации можно передать через `--config FILE`.

Форматы ссылок:

```text
tg://proxy?server=ENTRY_HOST&port=443&secret=EE_SECRET
https://t.me/proxy?server=ENTRY_HOST&port=443&secret=EE_SECRET
```

Полный пример для entry-хоста `203.0.113.10`, TLS-домена `example.com` и тестового секрета `0123456789abcdef0123456789abcdef`:

```text
tg://proxy?server=203.0.113.10&port=443&secret=ee0123456789abcdef0123456789abcdef6578616d706c652e636f6d
https://t.me/proxy?server=203.0.113.10&port=443&secret=ee0123456789abcdef0123456789abcdef6578616d706c652e636f6d
```

В ссылке указывается публичный адрес и входящий порт entry-хоста. Backend-порт exit-хоста `8443` в ссылку не входит. HTTPS-вариант содержит те же параметры и отличается только префиксом.
