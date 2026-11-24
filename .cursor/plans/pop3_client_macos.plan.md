---
name: POP3 клиент macOS
overview: "Нативный почтовый клиент для macOS на Swift и SwiftUI: несколько аккаунтов с общими папками, у каждого аккаунта свой протокол (POP3 или IMAP), интерфейс на русском и английском с возможностью добавить языки без изменения кода. Приоритет у понятности интерфейса. Приём, чтение, отправка и основные настройки; OAuth2 для Gmail и Outlook; сборка для личного использования."
todos:
  - id: env
    content: "Установить Xcode, xcodegen, swiftlint, swiftformat, xcbeautify, Docker + GreenMail; завести тестовые ящики и пароли приложений. Сделано: Xcode (выбран через xcode-select), brew-утилиты, Docker, GreenMail (docker-compose.yml), ящик mail.ru с паролем приложения Vermail, git-репозиторий"
    status: completed
  - id: skeleton
    content: "Каркас проекта: XcodeGen project.yml, SPM-модули, AGENTS.md/правила для агентов, CI-скрипт сборки и тестов, локализация ru/en. Сделано: пакет Packages/VermailKit (6 модулей-заглушек с тестами), приложение с 3-колоночным окном и настройкой языка, Localizable.xcstrings, scripts/ci.sh. GitHub Actions не подключали (macOS-раннеры для приватного репозитория платные)"
    status: completed
  - id: transport
    content: "MailTransport: SSL/STARTTLS, недействительные сертификаты, логирование. Сделано: протокол MailConnection, StreamConnection на URLSessionStreamTask (вместо NWConnection: тот не умеет STARTTLS), явная проверка сертификата, редактирование паролей в логе, защита от данных до TLS-рукопожатия. Тесты: юнит, GreenMail, live на mail.ru (SSL 995, STARTTLS 587)"
    status: completed
  - id: pop3
    content: "POP3Kit: команды, аутентификация (USER/PASS, APOP, PLAIN, LOGIN, CRAM-MD5, XOAUTH2), тесты на GreenMail. Сделано: POP3Client с MailFetching (connect, CAPA, UIDL/LIST, RETR, DELE, QUIT), поддержка STLS/STARTTLS через MailTransport, тесты со script-connection и интеграционный тест на GreenMail"
    status: completed
  - id: smtp
    content: "SMTPKit: EHLO/STARTTLS/AUTH/DATA, тесты на GreenMail. Сделано: SMTPClient (EHLO, STARTTLS, AUTH PLAIN/LOGIN/CRAM-MD5/XOAUTH2, MAIL FROM/RCPT TO/DATA/QUIT), dot-stuffing, script-тесты и интеграционный GreenMail-тест с проверкой доставки через POP3"
    status: completed
  - id: mime
    content: "MIMEKit: парсинг/сборка, кодировки koi8-r/cp1251, RFC 2047/2231, вложения. Сделано: MIME parser (headers, multipart, quoted-printable/base64, RFC2047, RFC2231 с continuation), MIME builder (plain/html/attachments, RFC2047 subject, RFC2231 filename, dot-safe body), тесты на разбор и roundtrip"
    status: completed
  - id: storage
    content: "MailStorage на GRDB + .eml на диске, FTS-поиск; SyncEngine с UIDL и политиками хранения на сервере. Сделано: MailDatabase (SQLite/GRDB), миграции schema v1, FTS5 индекс message_search, хранение raw .eml по account/uid, upsert/list/search/remove, POP3 sync plan по UIDL, тесты на upsert/поиск/unified scope/sync-plan"
    status: completed
  - id: accounts
    content: "Аккаунты: Keychain, пресеты серверов (mail.ru и др.), автоконфиг ISPDB, OAuth2 для Gmail/Outlook. Сделано: модели серверных настроек в MailAccount, каталог пресетов популярных провайдеров, MailAutoconfigService (preset + ISPDB), KeychainSecretStore/InMemorySecretStore, OAuthConfigurationCatalog для Gmail/Outlook, тесты на автоконфиг/пресеты/секреты/OAuth"
    status: completed
  - id: ui-main
    content: "Главное окно: 3 колонки, список писем, просмотр HTML в WKWebView с блокировкой внешних картинок, вложения. Сделано: расширения MailStorage (setRead, moveMessages, deleteMessages, unreadOnly, allMail, unreadCounts), AccountStore, MailSyncEngine, MessageMetadataExtractor, RemoteImagePolicyStore, MainWindowViewModel, 3-колоночный UI (MailboxSidebar, MessageRowView, MessageDetailView, MessageWebView с WKContentRuleList, AttachmentBarView с Quick Look и сохранением), локализация ru/en и тесты"
    status: completed
  - id: ui-compose
    content: "Окно составления письма: получатели, редактор, вложения, подпись, черновики. Сделано: ComposeView с полями Кому/Копия/Скрытая копия и автодополнением, выбор отправителя и псевдонима, подпись, вложения drag-and-drop, сохранение черновиков и отправка через SMTP с локальной копией в Отправленные, ответы и пересылка"
    status: completed
  - id: ui-settings
    content: "Окна настроек аккаунта (вкладки) и общих настроек (сайдбар). Сделано: боковые общие настройки (аккаунты, язык, единый ящик, звуки, Dock, уведомления, отметка прочитанным, составление, внешний вид, сообщения), редактор аккаунта с вкладками «Пользователь», «Папки», «Псевдоним», «Подпись» и «Ещё», проверка POP/SMTP, мастер добавления с автоконфигом. Сохранение вложения кладёт файл в «Загрузки». Папки IMAP сопоставляются автоматически"
    status: completed
  - id: system
    content: "Уведомления, бейдж в Доке, фоновая проверка по таймеру, локализация ru/en. Сделано: проверка включённых аккаунтов по их интервалу и при пробуждении Mac, бейдж непрочитанных во входящих, локальные уведомления и звук о новой почте, значок в строке меню. Первая загрузка ящика не уведомляет о каждом старом письме"
    status: completed
  - id: qa
    content: "QA MVP. Сделано: матрица серверов mail.ru/Yandex/Gmail/Outlook, GreenMail-сценарий отправки и приёма, политики POP3 (оставить на сервере, удалить через N дней, удалить после очистки корзины), поиск с кириллицей и пунктуацией, уведомления после опустошения ящика, пароль приложения в мастере Gmail/Outlook, фильтр непрочитанных не закрывает открытое письмо. scripts/ci.sh зелёный. Живой вход в четыре ящика и браузерный OAuth не выполнялись: нет client id Google/Microsoft"
    status: completed
  - id: imap
    content: "IMAPKit: LOGIN и AUTHENTICATE PLAIN/LOGIN/CRAM-MD5/XOAUTH2, STARTTLS, LIST/SELECT/UID FETCH, UID STORE, UID MOVE и EXPUNGE. Прочитанность, удаление и перемещение записываются на сервер, локальный ключ письма обновляется по COPYUID. Сопоставление SPECIAL-USE и известных имён с общими папками, выбор протокола в мастере и редакторе. Версия приложения 0.9.0"
    status: completed
  - id: updates
    content: "Самообновление с GitHub Releases: в «Общих» проверка раз в N дней, окно «Обновить сейчас», «Напомнить позже» и «Пропустить эту версию». VermailUpdater вне песочницы заменяет запущенную копию и открывает её снова. Архив релиза — Vermail-macos.zip"
    status: completed
isProject: false
---

# План: собственный POP3/SMTP почтовый клиент для macOS

## 0. Ключевые требования

- **Несколько аккаунтов.** Клиент работает с любым числом почтовых ящиков и собирает письма со всех в общие папки («Входящие», «Отправленные» и т.д.). Для каждого аккаунта можно отключить участие в общих папках и посмотреть его папки отдельно.
- **Свой протокол у каждого аккаунта.** У одного аккаунта POP3, у другого IMAP. Модель данных, синхронизация и UI не завязаны на конкретный протокол.
- **Языки.** Сейчас русский и английский. Новый язык добавляется только переводом в String Catalog, без изменений кода. Список языков в настройках строится из переводов, вошедших в сборку.
- **Интерфейс.** Приоритет: здравый смысл, интуитивность и [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines). Отдельных макетов в репозитории нет.

## 1. Стек разработки

- **Язык и UI:** Swift 6 и SwiftUI. Где SwiftUI не хватает, используем AppKit: таблицу писем, панель инструментов окна, `NSTextView` в редакторе. Минимальная версия: macOS 14 (Sonoma). Архитектура: Apple Silicon (arm64).
- **Сеть:** `URLSessionStreamTask` (Foundation). Выбран вместо `NWConnection`, потому что умеет переключать уже открытое соединение на TLS (`startSecureConnection()`), а это нужно для STARTTLS и STLS. Сертификат сервера проверяется явно через `SecTrustEvaluateWithError`. POP3 и SMTP-клиент пишем сами: протоколы простые, а зрелых Swift-библиотек для POP3 нет. Запасной вариант: MailCore2 (Objective-C), он старый и тяжёлый.
- **MIME:** собственный модуль для разбора и сборки MIME:
  - multipart, base64, quoted-printable, RFC 2047 и RFC 2231 для имён файлов;
  - кодировки `koi8-r`, `windows-1251`, `utf-8` (критично для писем с mail.ru) через `CFStringConvertEncodingToNSStringEncoding`.
- **Хранение:**
  - SQLite через [GRDB.swift](https://github.com/groue/GRDB.swift): метаданные писем, папки, UIDL, полнотекстовый поиск FTS5;
  - исходные `.eml` файлы на диске в `~/Library/Application Support/<App>/`.
- **Секреты:** Keychain (Security.framework) для паролей и OAuth-токенов.
- **Отображение HTML:** `WKWebView` с блокировкой внешних картинок через `WKContentRuleList`. Пользователь может загрузить картинки один раз или всегда для отправителя. JavaScript отключён.
- **OAuth2:** `ASWebAuthenticationSession` и PKCE, механизм `XOAUTH2` для POP3 и SMTP. Для Gmail нужен OAuth client в Google Cloud Console, для Outlook — регистрация приложения в Azure (Microsoft Entra).
- **Сборка проекта:** XcodeGen (`project.yml`), чтобы ИИ-агенты правили YAML, а не хрупкий `.pbxproj`. Модули оформляем как локальные Swift Package.
- **Локализация:** String Catalogs (`.xcstrings`), русский и английский с первого этапа. Каждая строка UI сразу получает перевод. `scripts/check-localizations.sh` требует полного перевода на русский и на любой язык, который появился в каталоге. Язык переключается в настройках, применяется после перезапуска. Добавление нового языка описано в [AGENTS.md](../../AGENTS.md).

## 2. Что установить в систему

Состояние на 12.11.2026 (актуальные версии в [AGENTS.md](../../AGENTS.md)):

- [x] **Xcode 27.2** установлен и выбран через `xcode-select`.
- [x] `brew install xcodegen swiftlint swiftformat xcbeautify`.
- [x] **Docker.app** для тестов (вместо OrbStack).
- [x] **GreenMail** поднят через [docker-compose.yml](../../docker-compose.yml), SMTP и POP3S проверены.
- [x] Ящик mail.ru с паролем приложения «Vermail».
- [x] Git-репозиторий, remote `https://github.com/Vladimir-Etherlord/vermail`.
- **Локальный тестовый почтовый сервер** [GreenMail](https://greenmail-mail-test.github.io/greenmail/) в Docker. Он поддерживает POP3, SMTP и IMAP с TLS и позволяет гонять интеграционные тесты без реальных ящиков.
- **Apple ID в Xcode** (бесплатный) для локальной подписи. Платный Developer-аккаунт не нужен, пока не понадобятся iCloud или нотаризация.
- **Тестовые ящики** на mail.ru, yandex, gmail и outlook. На mail.ru и yandex нужно создать «пароль для внешнего приложения».

## 3. Архитектура

```mermaid
flowchart TD
    UI["App UI (SwiftUI/AppKit)"] --> VM[ViewModels]
    VM --> Sync[SyncEngine]
    VM --> Compose[ComposeService]
    Sync -->|"по аккаунту"| FetchProto["MailFetching"]
    FetchProto -->|"pop3"| POP3Kit
    FetchProto -->|"imap"| IMAPKit
    Compose --> SMTPKit
    POP3Kit --> Transport["MailTransport (URLSessionStreamTask + TLS)"]
    IMAPKit --> Transport
    SMTPKit --> Transport
    Sync --> MIMEKit
    Compose --> MIMEKit
    Sync --> Storage["Storage (GRDB + .eml)"]
    VM --> Accounts["Accounts (Keychain, OAuth2, автоконфиг)"]
```

Модули (библиотеки внутри одного локального SPM-пакета `Packages/VermailKit`):

- **`MailTransport`:** соединение, TLS и STARTTLS, режим «разрешить недействительный сертификат», таймауты, логирование протокольного обмена.
- **`POP3Kit`:** команды USER/PASS, APOP, AUTH (PLAIN, LOGIN, CRAM-MD5, XOAUTH2), STAT, LIST, UIDL, TOP, RETR, DELE, CAPA, STLS.
- **`IMAPKit`:** LOGIN, AUTHENTICATE (PLAIN, LOGIN, CRAM-MD5, XOAUTH2), STARTTLS, CAPABILITY, LIST, SELECT, UID FETCH, UID STORE, EXPUNGE.
- **`SMTPKit`:** EHLO, STARTTLS, AUTH (PLAIN, LOGIN, CRAM-MD5, XOAUTH2), MAIL FROM, RCPT TO, DATA, dot-stuffing.
- **`MIMEKit`:** парсер и билдер писем.
- **`MailStorage`:** схема БД, миграции, FTS-поиск.
- **`MailCore`** (своё имя, не путать с MailCore2): доменные модели и протокол `MailFetching`. Уже есть `MailAccount` (с полем `incomingProtocol`: `pop3` или `imap`), `MailFolderKind` (общие папки) и `Mailbox` (папка во всех аккаунтах или в одном).
- **`App`:** UI.

## 4. Несколько аккаунтов и общие папки

- Каждое письмо в базе хранит `accountID` и папку `MailFolderKind`. Общая папка — это выборка по всем аккаунтам, у которых включено участие в общих папках. Папка одного аккаунта — та же выборка с фильтром по аккаунту.
- Боковая панель: сверху «Все аккаунты» с общими папками. Ниже, если аккаунтов больше одного, по секции на аккаунт.
- В списке писем общей папки видно, к какому аккаунту относится письмо (цвет или значок аккаунта).
- Ответ отправляется с того аккаунта, на который пришло письмо. Новое письмо — с аккаунта по умолчанию, выбор отправителя в окне написания.
- `SyncEngine` проверяет аккаунты параллельно и независимо: ошибка одного аккаунта не мешает остальным и показывается у этого аккаунта.
- Реализация `MailFetching` выбирается по `incomingProtocol` аккаунта. POP3 только приносит письма во «Входящие», а прочитанность и папки меняет локально. IMAP отображает серверные папки на `MailFolderKind` по атрибутам SPECIAL-USE и известным именам, скачивает их в общие папки и записывает на сервер прочитанность, удаление и перемещение.

## 5. Особенности POP3, которые надо учесть

- POP3 видит только папку «Входящие» на сервере. Для POP3-аккаунтов папки «Черновики», «Отправленные», «Корзина», «Спам», «Архив» и «Вся почта» **локальные**.
- По UIDL отслеживаем уже скачанные письма. Настройки:
  - «оставлять копии на сервере»;
  - «удалять с сервера через N дней»;
  - «удалять с сервера при удалении из корзины».
- Отправленные письма сохраняем в локальную папку «Отправленные». mail.ru сам кладёт копию в «Отправленные» на сервере, но по POP3 её не видно.
- Встроенные пресеты серверов: mail.ru (`pop.mail.ru:995 SSL`, `smtp.mail.ru:465 SSL`), Yandex, Gmail, Outlook/Hotmail, iCloud, Rambler. Для остальных доменов: автоконфиг через Mozilla ISPDB (`autoconfig.thunderbird.net`) и подбор по DNS MX.

## 6. Объём MVP по экранам

Состав полей, вкладок и разделов ниже — отправная точка: если что-то можно сделать понятнее, делаем понятнее.

- **Главное окно.** Три колонки на `NavigationSplitView`:
  - общие папки и папки аккаунтов, кнопка обновления;
  - список писем с аватаром и инициалами, отправителем, темой, превью, датой и значком вложения; переключатель «только непрочитанные», поиск;
  - просмотр письма: заголовки, HTML-тело, панель действий (ответить, ответить всем, переслать, удалить, переместить), блок вложений с Quick Look. Сохранение вложения кладёт файл в «Загрузки».
- **Окно написания письма:**
  - поля «Кому», «Копия», «Скрытая копия» с автодополнением из истории;
  - выбор отправителя и псевдонима;
  - простой rich-text или plain-text редактор, вложения через drag-and-drop, подпись, сохранение черновика.
- **Настройки аккаунта**, вкладки:
  - «Пользователь»: имя, описание, иконка и цвет, протокол POP3 или IMAP, серверы с портом, шифрованием и типом аутентификации, кнопки проверки входящего и исходящего;
  - «Папки», «Псевдоним», «Подпись»;
  - «Ещё»: интервал проверки. Для POP3 — оставлять на сервере и удалять через N дней. Для IMAP почта остаётся на сервере.
- **Общие настройки** (окно с боковым списком). В MVP разделы:
  - «Аккаунты»;
  - «Общие»: язык, единый ящик, звуки, иконка в Доке, уведомления, «отметить прочитанным через N сек», проверка обновлений раз в N дней;
  - «Составление»;
  - «Внешний вид»;
  - «Сообщения».
- **Мастер добавления аккаунта:** ввести email, затем автоопределение серверов, пароль или OAuth, проверка соединения.
- **Системное:** уведомления (`UserNotifications`), бейдж непрочитанных на иконке в Доке, проверка почты по таймеру и при пробуждении из сна, пункт в строке меню (опционально).

После текущей версии: правила, отложенные письма, «отправить позже», синхронизация через iCloud (нужен платный Developer-аккаунт), горячие клавиши.

## 7. Как работать с ИИ-агентами

- [AGENTS.md](../../AGENTS.md) в корне описывает стек, структуру модулей, код-стайл, локализацию и команды. Полная проверка запускается одной командой `scripts/ci.sh`.
- Сначала протокольные модули с unit-тестами на записанных диалогах сервера, затем интеграционные тесты на GreenMail, и только потом UI. Так агенты могут проверять себя без ручного тестирования.
- Каждый этап делать отдельной небольшой задачей с проверяемым результатом: тесты зелёные, проект собирается.
