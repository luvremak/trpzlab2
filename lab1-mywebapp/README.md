# mywebapp — Simple Inventory Service

Лабораторна робота №1 — «Розгортання Web-сервісу з автоматизацією».

Проєкт реалізує простий веб-сервіс обліку обладнання, розгортає його на
віртуальній машині Linux разом із базою даних та reverse-proxy, і повністю
автоматизує встановлення одним скриптом.

---

## 1. Варіант індивідуального завдання

Варіант розраховується від числа **N = 11** (порядковий номер у списку групи).

| Формула | Обчислення | Значення |
|---|---|---|
| V2 = (N % 2) + 1 | (11 % 2) + 1 = 1 + 1 | **2** |
| V3 = (N % 3) + 1 | (11 % 3) + 1 = 2 + 1 | **3** |
| V5 = (N % 5) + 1 | (11 % 5) + 1 = 1 + 1 | **2** |

Що це означає для реалізації:

| Параметр | Значення | Наслідок |
|---|---|---|
| **V3 = 3** | Тематика застосунку | **Simple Inventory** — сервіс обліку обладнання |
| **V2 = 2** | Спосіб конфігурації | Конфігураційний **файл** `/etc/mywebapp/config.toml` (формат — TOML) |
| **V2 = 2** | СУБД | **PostgreSQL** |
| **V5 = 2** | Порт застосунку | **5200** |

Назва застосунку незалежно від варіанту — `mywebapp`.

Архітектура системи (усі компоненти на одній ВМ):

```
client → nginx (reverse proxy, :80) → mywebapp (127.0.0.1:5200) → PostgreSQL (127.0.0.1:5432)
```

| Компонент | Адреса | Порт |
|---|---|---|
| nginx | 0.0.0.0 | 80 |
| mywebapp | 127.0.0.1 | 5200 |
| PostgreSQL | 127.0.0.1 | 5432 |

База даних і сам застосунок слухають лише на `127.0.0.1`, тобто доступні
тільки з самої віртуальної машини. Клієнти ззовні взаємодіють із системою
виключно через nginx.

---

## 2. Документація по веб-застосунку

### 2.1. Призначення

**Simple Inventory** — сервіс обліку обладнання. Дозволяє вести список
предметів інвентарю та переглядати детальну інформацію по кожному з них.
Об'єкт інвентарю `item` має поля:

| Поле | Тип | Опис |
|---|---|---|
| `id` | integer | Унікальний ідентифікатор (генерується БД) |
| `name` | text | Назва предмета |
| `quantity` | integer | Кількість (≥ 0) |
| `created_at` | timestamptz | Час створення запису (генерується БД) |

### 2.2. Технології

- **Мова / фреймворк:** Python 3.12 + FastAPI (ASGI-сервер — uvicorn)
- **СУБД:** PostgreSQL 16, драйвер — `psycopg` 3
- **Reverse proxy:** nginx
- **Запуск:** systemd із socket activation

### 2.3. Структура репозиторію

```
mywebapp/
├── app/                      # код веб-застосунку
│   ├── __init__.py
│   ├── config.py             # читання конфігураційного файлу (TOML)
│   ├── db.py                 # пул з'єднань до PostgreSQL
│   ├── migrate.py            # скрипт міграції бази даних
│   └── main.py               # FastAPI-застосунок, усі ендпоінти
├── deploy/                   # усе для розгортання
│   ├── install.sh            # ★ єдина точка входу автоматизації
│   ├── config.toml           # зразок конфігураційного файлу
│   ├── mywebapp.socket       # systemd socket (socket activation)
│   ├── mywebapp.service      # systemd service (фінальна версія)
│   ├── mywebapp.service.simple  # проста версія unit (проміжний крок)
│   ├── nginx-mywebapp.conf   # конфігурація nginx
│   └── sudoers-operator      # обмежені права sudo для operator
├── requirements.txt          # залежності Python
└── README.md                 # цей файл
```

### 2.4. Конфігураційний файл

Формат — **TOML**, шлях за замовчуванням — `/etc/mywebapp/config.toml`.
Шлях можна перевизначити змінною оточення `MYWEBAPP_CONFIG` (зручно для
розробки). Зразок — `deploy/config.toml`:

```toml
[server]
host = "127.0.0.1"
port = 5200

[database]
host = "127.0.0.1"
port = 5432
name = "mywebapp"
user = "mywebapp"
password = "..."
```

Секція `[server]` використовується, коли застосунок запускається **без**
socket activation. У фінальному варіанті з socket activation сокет
створює systemd (`deploy/mywebapp.socket`, директива `ListenStream`), тому
порт у конфігу має співпадати з портом у `.socket`-файлі.

### 2.5. Налаштування середовища для розробки / тестування

На машині розробника (приклад для Ubuntu/Debian):

```bash
# 1. Системні залежності
sudo apt-get install -y python3 python3-venv postgresql

# 2. Віртуальне оточення та залежності Python
cd mywebapp
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# 3. Локальна база даних
sudo -u postgres psql -c "CREATE ROLE mywebapp LOGIN PASSWORD 'devpass';"
sudo -u postgres createdb -O mywebapp mywebapp

# 4. Локальний конфіг (копія зразка)
cp deploy/config.toml /tmp/config.toml
# відредагувати password = "devpass" у /tmp/config.toml
export MYWEBAPP_CONFIG=/tmp/config.toml

# 5. Міграція бази даних
.venv/bin/python -m app.migrate

# 6. Запуск застосунку
.venv/bin/uvicorn app.main:app --host 127.0.0.1 --port 5200
```

### 2.6. Скрипт міграції бази даних

`app/migrate.py` підключається до БД, описаної в конфігу, і приводить її
схему до версії, потрібної поточному застосунку.

- Версія схеми зберігається в таблиці `schema_version`.
- Міграції в `MIGRATIONS` застосовуються по порядку, кожна рівно один раз.
- Скрипт **ідемпотентний**: повторний запуск на актуальній БД нічого не
  робить.
- Працює як на порожній БД, так і на БД попередньої версії, створеній цим
  же скриптом.
- Якщо БД новіша, ніж підтримує застосунок, скрипт завершується з помилкою
  (ненульовий код виходу), і systemd не запускає несумісний сервіс.

Запуск вручну: `python -m app.migrate`. Автоматично міграція виконується
перед кожним стартом сервісу (директива `ExecStartPre` в unit-файлі).

### 2.7. Документація по API

Усі ендпоінти бізнес-логіки підтримують **content negotiation** за
заголовком `Accept`:

- `Accept: text/html` → проста HTML-сторінка (списки — у вигляді таблиць,
  без JavaScript і без стилів);
- `Accept: application/json` → дані у форматі JSON;
- якщо клієнт не вказав вподобань (`*/*`, як curl за замовчуванням) →
  повертається JSON.

| Метод | Шлях | Опис | Тіло запиту | Відповідь |
|---|---|---|---|---|
| `GET` | `/` | Список усіх ендпоінтів бізнес-логіки. Приймає та віддає **тільки** `text/html` (інакше `406`) | — | `200` HTML |
| `GET` | `/items` | Список усіх предметів інвентарю (`id`, `name`) | — | `200` JSON/HTML |
| `POST` | `/items` | Створити новий предмет | JSON `{"name": str, "quantity": int}` | `201` створений об'єкт; `422` при невалідних даних |
| `GET` | `/items/{id}` | Повна інформація по предмету (`id`, `name`, `quantity`, `created_at`) | — | `200` об'єкт; `404` якщо не знайдено |
| `GET` | `/health/alive` | Liveness-проба — завжди `200` з тілом `OK` | — | `200 OK` |
| `GET` | `/health/ready` | Readiness-проба — `200 OK`, якщо є з'єднання з БД, інакше `500` з описом | — | `200` / `500` |

**Важливо:** ендпоінти `/health/*` призначені для внутрішнього моніторингу
і **не публікуються** назовні через nginx (див. розділ 3.6).

Приклади запитів:

```bash
# Список (JSON)
curl http://<vm-ip>/items

# Список (HTML)
curl -H "Accept: text/html" http://<vm-ip>/items

# Створити предмет
curl -X POST -H "Content-Type: application/json" \
     -d '{"name": "Дриль", "quantity": 5}' \
     http://<vm-ip>/items

# Деталі предмета
curl http://<vm-ip>/items/1

# Кореневий ендпоінт (тільки HTML)
curl -H "Accept: text/html" http://<vm-ip>/
```

### 2.8. Запуск веб-застосунку на ВМ

Після розгортання застосунок працює як systemd-сервіс із socket
activation і не потребує ручного запуску. Керування (від `root` або
користувача `operator` через `sudo`):

```bash
sudo systemctl status mywebapp.service     # стан
sudo systemctl restart mywebapp.service    # перезапуск
sudo systemctl stop mywebapp.service       # зупинка
sudo systemctl start mywebapp.socket       # активувати сокет
```

---

## 3. Документація по розгортанню

### 3.1. Базовий образ віртуальної машини

Використовується офіційний образ **Ubuntu Server 24.04 LTS**.

- Сторінка завантаження: <https://ubuntu.com/download/server>
- Завантажувати: **Ubuntu Server 24.04 LTS**, файл
  `ubuntu-24.04.x-live-server-amd64.iso` (для архітектури x86-64).

Для гіпервізорів, що підтримують готові образи (наприклад, cloud-образи
для libvirt/KVM, Multipass, Vagrant), можна використати офіційний
cloud-образ Ubuntu 24.04 — у ньому вже є типовий користувач `ubuntu`.

### 3.2. Вимоги до ресурсів віртуальної машини

| Ресурс | Мінімум | Рекомендовано |
|---|---|---|
| CPU | 1 vCPU | 2 vCPU |
| RAM | 1 GiB | 2 GiB |
| Диск | 10 GiB | 15 GiB |
| Мережа | 1 інтерфейс із доступом до Інтернету (для встановлення пакетів) | — |

### 3.3. Спеціальні налаштування при встановленні ОС

Особливих вимог немає. Достатньо стандартної інсталяції Ubuntu Server:

- розбивка диску — за замовчуванням (один кореневий розділ, LVM або без —
  не принципово);
- під час встановлення увімкнути **OpenSSH server**, щоб мати віддалений
  доступ;
- створити стандартного користувача (в офіційних cloud-образах це
  `ubuntu`) — цей користувач буде заблокований автоматизацією після
  первинного налаштування.

### 3.4. Як увійти на ВМ та які credentials використовувати

До запуску автоматизації — вхід під **типовим користувачем образу**:

- **cloud-образ:** користувач `ubuntu`, автентифікація за SSH-ключем, який
  ви вказали при створенні ВМ;
- **встановлення з ISO:** користувач і пароль, які ви задали в інсталяторі.

Доступ:

```bash
ssh ubuntu@<vm-ip>          # cloud-образ (SSH-ключ)
# або вхід через консоль гіпервізора
```

> Автоматизація **блокує** типового користувача наприкінці роботи. Після
> розгортання входити можна лише під створеними користувачами (див.
> розділ 3.7).

### 3.5. Як завантажити та запустити автоматизацію розгортання

```bash
# 1. На віртуальній машині, під типовим користувачем, отримати репозиторій
git clone <URL-репозиторію> mywebapp
cd mywebapp

# 2. Запустити єдину точку входу автоматизації з правами root
sudo ./deploy/install.sh
```

Скрипт `deploy/install.sh` виконує по кроках:

1. встановлює системні пакети (`python3-venv`, `postgresql`, `nginx`);
2. створює користувачів `app`, `student`, `teacher`, `operator`;
3. створює базу даних PostgreSQL та роль `mywebapp`;
4. генерує конфігураційний файл `/etc/mywebapp/config.toml` (з випадковим
   паролем БД);
5. розгортає код у `/opt/mywebapp` та створює віртуальне оточення;
6. встановлює systemd socket і service;
7. виконує міграцію БД і запускає сервіс;
8. налаштовує nginx як reverse proxy;
9. встановлює політику `sudo` для користувача `operator`;
10. створює файл `/home/student/gradebook` з числом `11`;
11. блокує типового користувача системи.

Скрипт **ідемпотентний** — його можна безпечно запускати повторно.

Після завершення сервіс доступний за адресою `http://<vm-ip>/`.

### 3.6. Reverse proxy (nginx)

nginx слухає на порту **80** і проксує запити на `127.0.0.1:5200`.

- Назовні публікуються **лише** кореневий ендпоінт `/` та ендпоінти
  бізнес-логіки `/items` і `/items/{id}`.
- Ендпоінти `/health/*` та будь-які інші шляхи назовні **недоступні**
  (nginx віддає на них `404`).
- Лог запитів пишеться у `/var/log/nginx/mywebapp_access.log`.

Конфігурація — `deploy/nginx-mywebapp.conf`, встановлюється у
`/etc/nginx/sites-available/mywebapp` і вмикається симлінком у
`sites-enabled`; стандартний сайт `default` вимикається.

### 3.7. Користувачі в системі

| Користувач | Призначення | Права | Пароль за замовчуванням |
|---|---|---|---|
| `student` | Користувач для роботи з проєктом | Адмін-права (група `sudo`); вхід по SSH-ключу типового користувача | — (SSH-ключ) |
| `teacher` | Користувач для перевірки роботи | Адмін-права (група `sudo`) | `12345678`, треба змінити при першому вході |
| `app` | Системний користувач, від якого працює застосунок | Мінімальні; без можливості входу (`nologin`) | — |
| `operator` | Керування сервісом mywebapp та nginx | Обмежений `sudo` (лише дозволені команди) | `12345678`, треба змінити при першому вході |

Користувач `operator` через `sudo` може виконувати **тільки**:

- запуск / зупинку / перезапуск / перегляд статусу `mywebapp.service` і
  `mywebapp.socket`;
- перезавантаження конфігурації nginx (`systemctl reload nginx`).

Політика описана у `deploy/sudoers-operator` → `/etc/sudoers.d/operator`.

> **Зауваження щодо імені системного користувача.** У тексті завдання
> розділ про systemd згадує користувача `mywebapp`, а підсумкова таблиця
> користувачів — користувача `app` із тим самим призначенням. У цій
> реалізації обрано ім'я **`app`**, як вказано в таблиці користувачів.
> Щоб змінити на `mywebapp`, достатньо замінити ім'я у `deploy/install.sh`
> (змінна `APP_USER`) та в unit-файлах (`User=`/`Group=`).

### 3.8. systemd: проста версія та socket activation

Розробка велася у два кроки, як вимагає завдання:

1. **Проста версія** — `deploy/mywebapp.service.simple`: звичайний
   systemd-сервіс, який сам біндить порт `5200` (бере його з конфігу).
   Файл збережено в репозиторії для демонстрації проміжного кроку.
2. **Фінальна версія — socket activation** — `deploy/mywebapp.socket` +
   `deploy/mywebapp.service`. Сокет `127.0.0.1:5200` створює systemd і
   передає його застосунку як файловий дескриптор (`uvicorn --fd 3`).
   Сервіс стартує автоматично при першому з'єднанні.

Автоматизація встановлює саме **фінальну версію** (socket activation).
В обох версіях сервіс працює від користувача `app` і виконує міграцію БД
перед запуском (`ExecStartPre`).

---

## 4. Інструкція з тестування розгорнутої системи

Нижче — перевірки, якими підтверджується коректність розгортання. Усі
команди виконуються на ВМ або з машини, що має мережевий доступ до ВМ.

### 4.1. Сервіси запущені

```bash
sudo systemctl status mywebapp.socket    # active (listening)
sudo systemctl status mywebapp.service   # active (running)
sudo systemctl status nginx              # active (running)
sudo systemctl status postgresql         # active
```

### 4.2. Health-ендпоінти (локально на ВМ)

```bash
curl -i http://127.0.0.1:5200/health/alive   # 200, тіло OK
curl -i http://127.0.0.1:5200/health/ready   # 200, тіло OK (БД доступна)
```

### 4.3. Бізнес-логіка через nginx (порт 80)

```bash
# Кореневий ендпоінт — список ендпоінтів, тільки HTML
curl -i -H "Accept: text/html" http://<vm-ip>/

# Створення предмета
curl -i -X POST -H "Content-Type: application/json" \
     -d '{"name": "Дриль", "quantity": 5}' http://<vm-ip>/items   # 201

# Список предметів — JSON
curl -i http://<vm-ip>/items

# Список предметів — HTML (таблиця)
curl -i -H "Accept: text/html" http://<vm-ip>/items

# Деталі предмета
curl -i http://<vm-ip>/items/1                                    # 200
curl -i http://<vm-ip>/items/9999                                 # 404

# Валідація вхідних даних
curl -i -X POST -H "Content-Type: application/json" \
     -d '{"name": "X", "quantity": -1}' http://<vm-ip>/items       # 422
```

### 4.4. nginx публікує лише дозволені шляхи

```bash
curl -o /dev/null -w "%{http_code}\n" http://<vm-ip>/health/alive  # 404
curl -o /dev/null -w "%{http_code}\n" http://<vm-ip>/health/ready  # 404
curl -o /dev/null -w "%{http_code}\n" http://<vm-ip>/docs          # 404
```

Лог запитів пишеться:

```bash
sudo tail -f /var/log/nginx/mywebapp_access.log
```

### 4.5. База даних доступна лише з ВМ

```bash
# З ВМ — з'єднання проходить
sudo -u postgres psql -d mywebapp -c "SELECT count(*) FROM items;"

# Ззовні ВМ — з'єднання має бути відхилене (PostgreSQL слухає лише localhost)
psql -h <vm-ip> -p 5432 -U mywebapp mywebapp   # connection refused
```

### 4.6. Права користувача operator

```bash
# Увійти як operator (пароль 12345678, система попросить змінити його)
ssh operator@<vm-ip>

# Дозволені команди — працюють
sudo systemctl restart mywebapp.service
sudo systemctl status mywebapp.service
sudo systemctl reload nginx

# Заборонені команди — sudo відмовляє
sudo systemctl restart postgresql      # відмова
sudo cat /etc/shadow                   # відмова
sudo apt-get update                    # відмова
```

### 4.7. Міграція бази даних ідемпотентна

```bash
cd /opt/mywebapp
sudo -u app env MYWEBAPP_CONFIG=/etc/mywebapp/config.toml \
     /opt/mywebapp/venv/bin/python -m app.migrate
# повторний запуск виводить "Schema is already at version 1; nothing to do."
```

### 4.8. Файл gradebook та блокування типового користувача

```bash
cat /home/student/gradebook            # має містити одне число: 11

# Типовий користувач заблокований — вхід неможливий
ssh ubuntu@<vm-ip>                     # доступ відхилено
```
