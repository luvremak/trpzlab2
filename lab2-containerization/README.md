# Лабораторна робота №2 — Контейнеризація

Репозиторій лабораторної роботи №2. Містить дослідницьку частину
(експерименти з контейнеризації Python-, Go- та власного застосунку) та
практичну частину (запуск системи з Лабораторної роботи №1 через Docker
Compose).

## Структура репозиторію

```
lab2-containerization/
├── python-experiments/    # дослідницька: Python-стартер (spaceship)
│   ├── Dockerfile.naive             експ. 1-2: наївний образ
│   ├── Dockerfile.optimized         експ. 3: оптимізація шарів
│   ├── Dockerfile.alpine            експ. 4: менший базовий образ (alpine)
│   ├── Dockerfile.numpy-debian      експ. 5: +numpy на debian
│   ├── Dockerfile.numpy-alpine      експ. 5: +numpy на alpine
│   ├── requirements-numpy.in        манифест залежностей з numpy
│   ├── api.py.numpy                 ендпоінт множення матриць 10x10
│   └── README.md                    як відтворити експерименти
├── golang-experiments/    # дослідницька: Go-стартер (fizzbuzz)
│   ├── Dockerfile.single-stage         експ. 1: одноетапна збірка
│   ├── Dockerfile.multistage-scratch   експ. 2: multi-stage + scratch
│   ├── Dockerfile.multistage-distroless експ. 3: multi-stage + distroless
│   └── README.md
├── dns-experiment/        # дослідницька: musl vs glibc (DNS)
│   └── README.md                    команди та що аналізувати
├── lab1-app/              # практична: контейнеризація системи з ЛР1
│   ├── docker-compose.yml           3 сервіси: db, app, nginx
│   ├── Dockerfile                   образ FastAPI-застосунку
│   ├── entrypoint.sh                міграція БД + запуск застосунку
│   ├── config.toml                  конфіг застосунку (db host = "db")
│   ├── nginx-mywebapp.conf          конфіг reverse proxy
│   ├── app/, requirements.txt       копія застосунку з ЛР1
│   └── README.md                    запуск через Docker Compose
├── scripts/
│   └── measure.sh                   замір часу збірки та розміру образу
├── report/
│   └── Звіт_ЛР2_Контейнеризація.docx звіт по дослідницькій частині
└── README.md
```

## Стартові проєкти для дослідницької частини

| Частина | Проєкт |
|---|---|
| Python | <https://github.com/KPI-FICT-MTSD/lab-03-starter-project-python> |
| Golang | <https://github.com/comsys-kpi-ua/deploy.lab-containers-starter-project-golang> |
| «Третій» застосунок | застосунок з Лабораторної роботи №1 (FastAPI + PostgreSQL), див. `lab1-app/` |

Dockerfile'и для Python- та Go-стартерів зберігаються тут окремо від
вихідного коду стартерів; перед збіркою їх треба скопіювати у клон
відповідного стартового репозиторію (інструкції — у `README.md` кожної
теки).

## Дослідницька частина — швидкий старт

Кожна тека `*-experiments/` має власний `README.md` з покроковими командами.
Заміри робляться скриптом `scripts/measure.sh`, який перед таймінгом збірки
завантажує базові образи окремо (щоб їх завантаження не входило в час
збірки).

```bash
cd python-experiments
../scripts/measure.sh Dockerfile.naive spaceship:naive .
```

Результати замірів зводяться у звіт `report/Звіт_ЛР2_Контейнеризація.docx`.

## Практична частина — швидкий старт

```bash
cd lab1-app
docker compose up --build -d
curl -i -H "Accept: text/html" http://localhost/
```

Деталі, перевірка персистентності БД та відповідність вимогам завдання —
у `lab1-app/README.md`.

## Примітка щодо розташування `docker-compose.yml`

За текстом завдання `docker-compose.yml` має знаходитися в репозиторії
Лабораторної роботи №1, а її README — доповнюватися інструкцією по запуску
через Docker Compose. У цьому репозиторії практична частина зібрана в теці
`lab1-app/`, яка є самодостатньою: її вміст можна скопіювати в репозиторій
ЛР1 без змін. `lab1-app/README.md` написаний так, щоб його можна було
перенести або злити з README ЛР1.

## Звіт

Звіт по дослідницькій частині — `report/Звіт_ЛР2_Контейнеризація.docx`.
Він містить методологію, команди для відтворення кожного експерименту,
таблиці результатів та висновки. Таблиці результатів містять порожні
комірки, які заповнюються реальними замірами після прогону експериментів
на конкретній машині (конфігурацію машини також треба вказати у звіті).
