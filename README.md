# Telemt: прокси через два хоста

Схема подключения:

```text
Telegram → entry-хост в России:443 → exit-хост за пределами России:8443 → Telegram
```

Между entry- и exit-хостами используется обычный NAT без дополнительного шифрования. Из-за MASQUERADE Telemt видит IP entry-хоста вместо IP клиента.

## 1. Exit-хост

На зарубежном сервере:

```sh
apt-get update && apt-get install -y git
git clone https://github.com/worthdone/alttab
cd alttab
sudo ./setup-exit.sh \
    --tls-domain example.com \
    --public-host 203.0.113.10
```

Замените `example.com` на домен для TLS-маскировки, а `203.0.113.10` — на публичный IP или домен российского entry-хоста. По умолчанию Telemt доступен на exit-хосте через порт `8443`.

Для другого backend-порта добавьте, например, `--backend-port 9443`. Разрешите этот порт в firewall exit-хоста, желательно только для IP entry-хоста.

## 2. Entry-хост

На российском сервере:

```sh
apt-get update && apt-get install -y git
git clone https://github.com/worthdone/alttab
cd alttab
sudo ./setup-entry.sh --backend-ip 206.189.74.192
```

Замените `206.189.74.192` на публичный IP exit-хоста. Если на exit-хосте выбран другой порт, передайте здесь тот же параметр:

```sh
sudo ./setup-entry.sh --backend-ip 206.189.74.192 --backend-port 9443
```

Входящий порт по умолчанию — `443`. Для ограничения конкретным интерфейсом добавьте `--interface eth0`. Скрипт сохраняет весь активный набор правил через `netfilter-persistent`.

## Ссылки Telegram

`setup-exit.sh` записывает в конфигурацию публичный адрес entry-хоста и выводит готовую `tg://`-ссылку. Получить обе полные ссылки из Docker-лога можно на exit-хосте:

```sh
TG_LINK="$(docker logs telemt 2>&1 | grep -o 'tg://proxy?[^[:space:]]*' | tail -n 1)"
HTTPS_LINK="$(printf '%s\n' "$TG_LINK" | sed 's|^tg://proxy?|https://t.me/proxy?|')"
printf '%s\n%s\n' "$TG_LINK" "$HTTPS_LINK"
```

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
