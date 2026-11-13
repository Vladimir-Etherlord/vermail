# Vermail — почтовый клиент для macOS

Перед началом любой задачи прочитай план разработки:
[.cursor/plans/pop3_client_macos.plan.md](.cursor/plans/pop3_client_macos.plan.md).

- Интерфейс строится по здравому смыслу и Apple Human Interface Guidelines. Отдельных макетов в репозитории нет.
- Стек: Swift 6, SwiftUI и AppKit, Network.framework, GRDB, Keychain, WKWebView, XcodeGen. Минимальная версия macOS 14.
- Объём: POP3, IMAP и SMTP, OAuth2 для Gmail и Outlook. Сборка только для личного использования. IMAP записывает на сервер прочитанность, удаление и перемещение. У POP3 это остаётся локальным.
- **Несколько аккаунтов, разные протоколы.** Аккаунтов может быть сколько угодно, письма со всех собираются в общие папки. У каждого аккаунта свой протокол (`MailAccount.incomingProtocol`: POP3 или IMAP). Код синхронизации, хранения и UI не должен предполагать один аккаунт или один протокол: работай через `MailFetching`, `MailAccount` и `Mailbox`, а не напрямую с POP3.
- Работай по этапам из раздела `todos` плана. После выполнения этапа отмечай его статус в плане как `completed`.
- Порядок: протокольные модули с тестами, затем интеграционные тесты на GreenMail, только потом UI.

## Окружение разработчика

Mac на Apple Silicon (arm64), macOS 27.2.

| Инструмент | Версия | Путь |
|---|---|---|
| Xcode | 27.2 (macOS SDK 27.2) | `/Applications/Xcode.app` |
| Swift | 6.4 | |
| XcodeGen | 2.46.0 | `/opt/homebrew/bin/xcodegen` |
| SwiftLint | 0.65.1 | `/opt/homebrew/bin/swiftlint` |
| SwiftFormat | 0.64.6 | `/opt/homebrew/bin/swiftformat` |
| xcbeautify | 3.2.1 | `/opt/homebrew/bin/xcbeautify` |
| Docker (Docker.app) | 28.0.1 | `/usr/local/bin/docker` |

Перед сборкой проверь две вещи:

- **Активный Xcode.** Если `xcode-select -p` указывает на `/Library/Developer/CommandLineTools`, `xcodebuild` работать не будет. Попроси пользователя выполнить `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`, сам `sudo` не запускай. Временный обход: префикс `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` перед командой.
- **Docker.** Интеграционным тестам нужен запущенный Docker.app. Если `docker info` выдаёт `Cannot connect to the Docker daemon`, запусти его командой `open -a Docker` и подожди, пока демон поднимется.

Команды выполняй вне песочницы, иначе нет доступа к Xcode, DerivedData и сокету Docker.

## Структура проекта

```text
project.yml                 # описание Xcode-проекта для XcodeGen
Vermail/                    # приложение (SwiftUI): App/, MainWindow/, Settings/, Localization/, Resources/
VermailTests/               # тесты приложения (Swift Testing)
Packages/VermailKit/        # один SPM-пакет, внутри модули-библиотеки:
  Sources/MailCore          #   MailAccount, MailFolderKind, Mailbox, протокол MailFetching (общий для POP3 и IMAP)
  Sources/MailTransport     #   MailConnection (протокол) и StreamConnection (URLSessionStreamTask, SSL и STARTTLS)
  Sources/POP3Kit           #   POP3-клиент
  Sources/IMAPKit           #   IMAP-клиент
  Sources/SMTPKit           #   SMTP-клиент
  Sources/MIMEKit           #   разбор и сборка писем
  Sources/MailStorage       #   SQLite (GRDB) и .eml на диске
  Tests/<Module>Tests       #   тесты каждого модуля
scripts/ci.sh               # полная проверка
scripts/check-localizations.sh
```

- Новый модуль добавляй как target в `Packages/VermailKit/Package.swift` и подключай в `project.yml`.
- Модули пакета не зависят от SwiftUI и не содержат текстов для пользователя. Ошибки отдают типизированными `enum`, а локализованный текст к ним добавляет приложение.
- Bundle ID: `com.etherlord.vermail`. Подпись ad-hoc (`CODE_SIGN_IDENTITY = -`), App Sandbox включён (`Vermail/Vermail.entitlements`, сеть и доступ к файлам, выбранным пользователем).
- Тесты пиши на Swift Testing (`import Testing`, `@Test`, `#expect`), не на XCTest.

## Команды

```bash
scripts/ci.sh                                    # всё сразу; должен быть зелёным перед каждым коммитом
xcodegen generate                                # пересоздать .xcodeproj из project.yml
xcodebuild -project Vermail.xcodeproj -scheme Vermail -destination 'platform=macOS,arch=arm64' build | xcbeautify
xcodebuild -project Vermail.xcodeproj -scheme Vermail -destination 'platform=macOS,arch=arm64' test | xcbeautify
swift test --package-path Packages/VermailKit    # тесты модулей (быстрее, без Xcode-проекта)
swift test --package-path Packages/VermailKit --filter POP3KitTests
swift test --package-path Packages/VermailKit --filter IMAPKitTests
swiftformat . && swiftlint --strict
```

- `.xcodeproj` генерируется, вручную его не правь и не коммить (он в `.gitignore`). Меняй `project.yml`.
- После правок кода запускай `scripts/ci.sh`.

## Локализация (русский и английский)

Интерфейс с самого начала двуязычный. Правила обязательны для любого UI-кода:

- Все тексты интерфейса живут в String Catalog [Vermail/Resources/Localizable.xcstrings](Vermail/Resources/Localizable.xcstrings). Исходный язык английский (ключ = английский текст), перевод на русский обязателен.
- В SwiftUI пиши строковые литералы: `Text("Inbox")`, `Button("Save")`, `Label("General", systemImage:)` — они локализуются автоматически. Для значений вне View используй `LocalizedStringResource` или `String(localized:)`. Не склеивай фразы из кусков, используй интерполяцию: `Text("\(count) messages")`, а для чисел — plural-варианты в каталоге (в русском формы one, few, many, other).
- Каждую новую строку сразу добавляй в `Localizable.xcstrings` с `"state" : "translated"` для `ru`. Сборка через `xcodebuild` не дописывает ключи в каталог сама, а `scripts/check-localizations.sh` (часть `ci.sh`) падает, если перевода нет.
- Строки, которые не надо переводить (названия языков, протоколов, серверов), выводи через `Text(verbatim:)`.
- Язык переключается в настройках («Общие» → «Язык»): `AppLanguage` пишет `AppleLanguages` в настройки приложения, применяется после перезапуска. Для ручной проверки можно запустить с аргументом `-AppleLanguages "(ru)"` или `"(en)"`.
- Список языков в настройках не задаётся в коде: `AppLanguage.available()` берёт языки из переводов в сборке, а название показывает на самом этом языке через `Locale`. Не добавляй в код перечислений или `switch` по языкам.

### Как добавить новый язык

1. Добавь перевод всех строк в `Localizable.xcstrings`: в Xcode через «+» внизу редактора каталога или правкой JSON (раздел `localizations.<код>` у каждой строки, например `de`, `uk`, `pt-BR`).
2. Запусти `scripts/ci.sh`. Проверка переводов покажет строки, которые остались без перевода на новый язык.
3. Пересобери приложение. Язык сам появится в настройках. Код менять не нужно.
- Даты, числа и размеры файлов форматируй через `FormatStyle` (`.formatted()`), а не вручную.

## Тестовый почтовый сервер (GreenMail)

Используется для интеграционных тестов POP3, IMAP и SMTP. Описан в [docker-compose.yml](docker-compose.yml) (контейнер `vermail-greenmail`):

```bash
docker compose up -d     # запустить
docker compose down      # остановить (почтовые ящики очищаются)
```

- Порты: SMTP 3025, SMTPS 3465, POP3 3110, POP3S 3995, IMAP 3143, IMAPS 3993.
- Тестовые пользователи (логин — email): `test@localhost` / `test`, `alice@localhost` / `alice`.
- Сертификат самоподписанный, поэтому в тестах включай режим «разрешить недействительный сертификат».
- Быстрая проверка: `curl -sk --user 'test@localhost:test' pop3s://localhost:3995/`.
- GreenMail **не поддерживает STARTTLS**. Переход на TLS проверяется live-тестами на реальных серверах.
- `scripts/ci.sh` сам поднимает контейнер и выставляет `VERMAIL_INTEGRATION=1`. Тесты, которым нужен GreenMail, помечай трейтом `.greenMail`, иначе при обычном `swift test` они упадут.
- Тесты против реальных серверов (без логина, только подключение) помечай трейтом `.liveServers`. В `ci.sh` они не запускаются. Ручной запуск:

  ```bash
  VERMAIL_INTEGRATION=1 VERMAIL_LIVE_TESTS=1 swift test --package-path Packages/VermailKit
  ```

- Протокольные клиенты (POP3, SMTP, IMAP) работают через протокол `MailConnection`, а не напрямую через `StreamConnection`. Так их можно тестировать на заранее записанных диалогах с сервером без сети.
- В `POP3Kit` уже реализованы: USER/PASS, APOP, AUTH PLAIN, AUTH LOGIN, AUTH CRAM-MD5, AUTH XOAUTH2, команды CAPA/UIDL/LIST/RETR/DELE/QUIT и dot-unstuff для RETR. При доработках сначала обновляй script-тесты в `POP3KitTests`, потом GreenMail-тест.
- В `IMAPKit` уже реализованы: LOGIN, AUTHENTICATE PLAIN/LOGIN/CRAM-MD5/XOAUTH2, STARTTLS, CAPABILITY, LIST, SELECT, UID FETCH (в том числе литералы тела), UID STORE, UID MOVE (или UID COPY и EXPUNGE) и EXPUNGE. Прочитанность, удаление и перемещение записываются на сервер, а локальный `remote_uid` обновляется по COPYUID. Папки SPECIAL-USE и известные имена сопоставляются с `MailFolderKind`. При доработках сначала обновляй script-тесты в `IMAPKitTests`, потом GreenMail-тест. У POP3 эти действия остаются локальными.
- В `SMTPKit` уже реализованы: EHLO, STARTTLS, AUTH PLAIN/LOGIN/CRAM-MD5/XOAUTH2, MAIL FROM/RCPT TO/DATA/QUIT и dot-stuffing для тела письма. При изменениях SMTP сначала правь script-тесты, затем интеграционный тест `SMTPGreenMailTests` (он проверяет доставку через POP3).
- В `MIMEKit` уже реализованы парсер и билдер: multipart, quoted-printable/base64, RFC 2047 (encoded-word), RFC 2231 (filename* и continuation), charset-декодирование (включая windows-1251 и koi8-r через IANA mapping), вложения и roundtrip-тесты. При изменениях MIME обязательно обновляй `MIMEKitTests` (особенно кейсы с cp1251/koi8-r и filename*).
- В `MailStorage` уже реализованы: `MailDatabase` на GRDB (`storage.sqlite` + миграции), FTS5-поиск (`message_search`), хранение raw `.eml` в `raw/<account>/<sha256(uid)>.eml`, операции upsert/list/search/remove и POP3 `UIDL` sync plan (`toDownload/alreadyKnown/missingOnServer`). При изменениях storage обязательно обновляй `MailStorageTests` и проверяй `scripts/ci.sh`.
- В `MailCore` для этапа accounts реализованы: `MailProviderPresets` (mail.ru/yandex/gmail/outlook/icloud/rambler), `MailAutoconfigService` (сначала preset, потом ISPDB `autoconfig.thunderbird.net`), `KeychainSecretStore` + `InMemorySecretStore`, `OAuthConfigurationCatalog` (Gmail/Outlook), и расширенные серверные настройки в `MailAccount` (`IncomingServerSettings`/`OutgoingServerSettings`).
- Для XOAUTH2 используй `OAuthConfigurationCatalog.xoauth2Payload(...)` и храни access/refresh токены через `AccountSecretStore` (в приложении — `KeychainSecretStore`).

Реальный ящик на mail.ru для ручных проверок у пользователя есть, пароль для внешнего приложения называется «Vermail». Логин и пароль спрашивай у пользователя, в репозиторий их не записывай.

## Git

- Репозиторий: [github.com/Vladimir-Etherlord/vermail](https://github.com/Vladimir-Etherlord/vermail), основная ветка `main`.
- Коммить по завершении каждого этапа или осмысленной части этапа. Сообщения коммитов пиши по-английски, кратко, в повелительном наклонении.

## Безопасность

Реальные пароли и OAuth-секреты (mail.ru, Yandex, Gmail, Outlook) не пиши в код, тесты и логи. В приложении они хранятся только в Keychain (связка «Вход»). Не переноси их в data protection keychain: у ad-hoc подписи нет keychain access group, и запись возвращает -34018. Окно связки при каждом запуске отладочной сборки ожидаемо, потому что подпись меняется при каждой компиляции. У сборки со стабильной подписью «Разрешать всегда» запоминается. Для ручных проверок пароль вводит пользователь. Сохранённые пользователем вложения кладутся в «Загрузки», отдельной настройки папки нет.
