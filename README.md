# Vermail

Нативный почтовый клиент для macOS. Несколько ящиков собираются в общие папки. Сейчас это личная сборка: приём по POP3, отправка по SMTP, чтение, поиск, ответы и настройки.

## Возможности

- Несколько аккаунтов. Письма попадают в общие «Входящие», «Отправленные», «Черновики», «Корзина», «Спам» и «Архив». Папки одного ящика можно смотреть отдельно.
- POP3 и SMTP, SSL и STARTTLS. IMAP ещё не сделан.
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

## Устройство проекта

```text
Vermail/                 приложение на SwiftUI
VermailTests/            тесты приложения
Packages/VermailKit/     почтовое ядро, независимое от интерфейса
  MailCore               аккаунты, папки, общие модели
  MailTransport          TCP-соединения, SSL/TLS, STARTTLS
  POP3Kit · SMTPKit      почтовые протоколы
  MIMEKit                разбор и сборка писем
  MailStorage            локальная база писем
```

## Стек

Swift 6 · SwiftUI · AppKit · Swift Testing · SQLite ([GRDB](https://github.com/groue/GRDB.swift)) · XcodeGen

## Разработка

Проект разрабатывается с помощью ИИ-агентов в [Cursor](https://cursor.com). Правила для агентов собраны в [AGENTS.md](AGENTS.md).
