# Vermail — POP3/SMTP почтовый клиент для macOS

Перед началом любой задачи прочитай план разработки:
[.cursor/plans/pop3_client_macos.plan.md](.cursor/plans/pop3_client_macos.plan.md).

- Макеты экранов лежат в `tz/`: `MainWindow.png` (главное окно), `SettingsWindow.png` (настройки аккаунта) и скриншот общих настроек.
- Стек: Swift 6, SwiftUI и AppKit, Network.framework, GRDB, Keychain, WKWebView, XcodeGen. Минимальная версия macOS 14.
- Объём: сначала MVP (POP3 и SMTP, OAuth2 для Gmail и Outlook), архитектура с заделом под IMAP. Сборка только для личного использования.
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

## Команды

```bash
xcodegen generate                                # пересоздать .xcodeproj из project.yml
xcodebuild -scheme Vermail -destination 'platform=macOS' build | xcbeautify
xcodebuild -scheme Vermail -destination 'platform=macOS' test | xcbeautify
swift test --package-path Packages/<Module>      # тесты отдельного SPM-модуля
swiftformat . && swiftlint
```

- `.xcodeproj` генерируется, вручную его не правь и не коммить. Меняй `project.yml`.
- После правок кода прогоняй `swiftformat`, `swiftlint` и тесты затронутых модулей.

## Тестовый почтовый сервер (GreenMail)

Используется для интеграционных тестов POP3 и SMTP. Описан в [docker-compose.yml](docker-compose.yml) (контейнер `vermail-greenmail`):

```bash
docker compose up -d     # запустить
docker compose down      # остановить (почтовые ящики очищаются)
```

- Порты: SMTP 3025, SMTPS 3465, POP3 3110, POP3S 3995, IMAP 3143, IMAPS 3993.
- Тестовые пользователи (логин — email): `test@localhost` / `test`, `alice@localhost` / `alice`.
- Сертификат самоподписанный, поэтому в тестах включай режим «разрешить недействительный сертификат».
- Быстрая проверка: `curl -sk --user 'test@localhost:test' pop3s://localhost:3995/`.

Реальный ящик на mail.ru для ручных проверок у пользователя есть, пароль для внешнего приложения называется «Vermail». Логин и пароль спрашивай у пользователя, в репозиторий их не записывай.

## Git

- Репозиторий: [github.com/Vladimir-Etherlord/vermail](https://github.com/Vladimir-Etherlord/vermail), основная ветка `main`.
- Коммить по завершении каждого этапа или осмысленной части этапа. Сообщения коммитов пиши по-английски, кратко, в повелительном наклонении.

## Безопасность

Реальные пароли и OAuth-секреты (mail.ru, Yandex, Gmail, Outlook) не пиши в код, тесты и логи. В приложении они хранятся только в Keychain. Для ручных проверок их вводит пользователь.
