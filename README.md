# Vermail

Нативный почтовый клиент для macOS. Несколько ящиков собираются в общие папки. Сейчас это личная сборка: приём по POP3 и IMAP, отправка по SMTP, чтение, поиск, ответы и настройки.

## Возможности

- Несколько аккаунтов. Письма попадают в общие «Входящие», «Отправленные», «Черновики», «Корзина», «Спам» и «Архив». Папки одного ящика можно смотреть отдельно.
- POP3, IMAP и SMTP, SSL и STARTTLS. IMAP скачивает входящие, отправленные, черновики, корзину, спам и архив и записывает на сервер прочитанность, удаление и перемещение. У POP3 остальные папки остаются только на этом Mac.
- Приложение само проверяет обновления на GitHub. В разделе «Общие» задаётся, раз в сколько дней это делать.
- Пароли хранятся в Связке ключей. Для Mail.ru и Яндекса нужен пароль приложения. Для Gmail и Outlook подготовлен OAuth2.
- Внешние картинки в письме не загружаются, пока это не разрешено для отправителя.
- Русский и английский. Новый язык добавляется переводом в каталог строк.
- Серверы определяются по адресу почты. Для популярных сервисов есть готовые настройки.
- Вложение из письма сохраняется в «Загрузки».

## Требования

- macOS 14 или новее, Apple Silicon
- Для сборки: Xcode и [Homebrew](https://brew.sh)

## Сборка

```bash
brew install xcodegen swiftlint swiftformat xcbeautify
git clone https://github.com/Vladimir-Etherlord/vermail.git && cd vermail
xcodegen generate
open Vermail.xcodeproj
```

Проект Xcode генерируется из [`project.yml`](project.yml), поэтому `Vermail.xcodeproj` в репозитории нет.

Полная проверка:

```bash
scripts/ci.sh
```

Интеграционным тестам нужен [GreenMail](https://greenmail-mail-test.github.io/greenmail/) в Docker: `docker compose up -d`.

## Обновление

Vermail смотрит [последний релиз](https://github.com/Vladimir-Etherlord/vermail/releases/latest) на GitHub. В релизе должен быть архив `Vermail-macos.zip` с `Vermail.app` внутри, а метка версии — новее текущей, например `v0.9.1`.

Архив из собранного приложения:

```bash
ditto -c -k --keepParent /path/to/Vermail.app Vermail-macos.zip
```

«Обновить сейчас» скачивает архив и заменяет ту копию, которая сейчас запущена. Перед этим приложение должно лежать в обычной папке, например в «Программах», а не во временном каталоге, куда macOS переносит только что загруженные программы.

## Устройство проекта

```text
Vermail/                 приложение на SwiftUI
VermailUpdater/          замена установленной копии при обновлении
VermailTests/            тесты приложения
Packages/VermailKit/     почтовое ядро, независимое от интерфейса
  MailCore               аккаунты, папки, общие модели
  MailTransport          TCP-соединения, SSL/TLS, STARTTLS
  POP3Kit · IMAPKit · SMTPKit   почтовые протоколы
  MIMEKit                разбор и сборка писем
  MailStorage            локальная база писем
```

## Стек

Swift 6 · SwiftUI · AppKit · Swift Testing · SQLite ([GRDB](https://github.com/groue/GRDB.swift)) · XcodeGen

## Разработка

Проект разрабатывается с помощью ИИ-агентов в [Cursor](https://cursor.com). Правила для агентов собраны в [AGENTS.md](AGENTS.md).
