# KleanBytes

KleanBytes — нативное приложение для macOS, которое помогает понять, чем занят диск, найти крупные файлы и папки, безопасно подготовить ненужные объекты к удалению и удалить приложения вместе со связанными данными.

Проект написан на Swift и SwiftUI. Интерфейс адаптируется к светлой и тёмной теме macOS.

> [!WARNING]
> KleanBytes умеет выполнять безвозвратное удаление без Корзины. Перед подтверждением внимательно проверяйте список. Системные области дополнительно проверяются и блокируются как интерфейсом, так и privileged helper.

## Возможности

- быстрый и полный анализ диска;
- навигация по дереву файлов и папок;
- сортировка содержимого по размеру;
- отображение размеров, количества файлов и вложенных каталогов;
- выбор сразу нескольких объектов;
- отдельное окно проверки выбранных объектов перед удалением;
- возможность убрать объект из выборки;
- временная разблокировка защищённых несистемных объектов с подтверждением владельца Mac;
- повторное усиленное подтверждение для ранее разблокированных объектов;
- постоянная блокировка критических системных областей macOS;
- удаление обычных объектов от имени пользователя;
- удаление объектов, требующих административных прав, через подписанный privileged helper;
- подробный результат: что было удалено, что удалить не удалось и почему;
- переход к объекту в Finder;
- настройка состава быстрого сканирования;
- деинсталлятор приложений со связанными файлами;
- возможность удалить только связанные данные, не удаляя сам пакет приложения;
- обнаружение запущенных приложений перед деинсталляцией;
- отображение занятого и свободного пространства;
- поддержка Full Disk Access;
- адаптивный интерфейс, светлая и тёмная темы.

## Режимы работы

### Быстрый анализ

Предназначен для регулярной проверки наиболее полезных пользовательских расположений. Он выполняется быстрее полного анализа и может учитывать пользовательскую конфигурацию включённых и исключённых путей.

На новом Mac первый процент выполнения является оценочным. После успешно завершённого сканирования KleanBytes сохраняет фактическое количество обработанных объектов в:

```text
~/Library/Preferences/com.alllyxer.KleanBytes.plist
```

Следующий запуск использует это значение для более точного прогресса. Для быстрого и полного анализа хранятся отдельные оценки.

### Полный анализ

Обходит доступную файловую систему значительно глубже. Результат зависит от разрешений текущего пользователя и Full Disk Access. Даже при полном доступе KleanBytes не обходит System Integrity Protection и собственные правила безопасности.

### Деинсталлятор

Показывает установленные приложения и связанные с ними данные:

- Application Support;
- кэши;
- настройки;
- сохранённое состояние;
- веб-данные;
- журналы;
- launch agents и launch daemons;
- privileged helpers;
- данные разработчика и установщиков.

Пакет приложения и каждый связанный объект можно включать или исключать из удаления отдельно. Это позволяет, например, очистить остаточные данные, оставив само приложение.

## Безопасность удаления

Удаление выполняется в несколько уровней:

1. Интерфейс классифицирует объект и ограничивает выбор критических путей.
2. Перед удалением строится новый план и каждый путь проверяется повторно.
3. Системные объекты исключаются из операции.
4. Обычные доступные объекты удаляются с правами пользователя.
5. Для объектов с повышенными требованиями запрашивается одноразовое разрешение администратора.
6. Privileged helper снова независимо проверяет каждый путь.

Запрещено удаление системных корней, защищённых деревьев macOS, домашнего каталога целиком, пакета самого KleanBytes и путей вне разрешённых областей.

Если удаление завершилось частично, приложение отдельно показывает удалённые и неудалённые пути с причинами.

## Разрешения macOS

### Full Disk Access

Full Disk Access позволяет увидеть больше пользовательских данных. Включается в:

```text
System Settings → Privacy & Security → Full Disk Access
```

Это разрешение не отменяет системную защиту и не разрешает удаление критических компонентов macOS.

### Background Item

Для административного удаления KleanBytes использует launch daemon:

```text
com.alllyxer.KleanBytes.PrivilegedHelper
```

macOS может попросить разрешить его в:

```text
System Settings → General → Login Items & Extensions
```

Helper находится внутри подписанного пакета приложения и регистрируется через `SMAppService`.

Helper не является отдельным приложением, которое пользователь должен запускать вручную. Основное приложение регистрирует его по plist:

```text
KleanBytes.app/Contents/Library/LaunchDaemons/com.alllyxer.KleanBytes.PrivilegedHelper.plist
```

Исполняемый файл helper находится здесь:

```text
KleanBytes.app/Contents/Resources/KleanBytesPrivilegedHelper
```

Основное приложение и helper взаимно проверяют Bundle ID, Team ID и кодовую подпись XPC-соединения. Поэтому их необходимо собирать и подписывать одной Apple Developer Team. Helper повторно проверяет полученные пути и не полагается только на решение интерфейса.

## Требования для разработки

- Mac с совместимой версией macOS;
- Xcode с macOS 27 SDK;
- Swift и SwiftUI из установленного Xcode;
- Apple ID, добавленный в Xcode;
- выбранная Signing Team для обоих targets;
- права администратора для проверки privileged helper.

Текущий deployment target проекта — macOS 27.0.

Targets:

- `KleanBytes` — основное приложение;
- `KleanBytesPrivilegedHelper` — административный helper.

Shared schemes проекта необходимо сохранять в репозитории:

```text
KleanBytes.xcodeproj/xcshareddata/xcschemes/
```

## Локальные иконки системных приложений

В интерфейсе предусмотрены локальные изображения для папок данных Safari, Mail, Messages, Photos, Shortcuts, Weather, Contacts, Reminders и Calendar. Код обращается к следующим именам Assets:

```text
SystemAppSafari
SystemAppMail
SystemAppMessages
SystemAppPhotos
SystemAppShortcuts
SystemAppWeather
SystemAppContacts
SystemAppReminders
SystemAppCalendar
```

Оригинальные иконки приложений Apple не входят в публичный репозиторий и исключены через `.gitignore`:

```gitignore
KleanBytes/Assets.xcassets/SystemApp*.imageset/
```

Это сделано, чтобы не распространять принадлежащие Apple графические ресурсы вместе с исходным кодом. Без этих imageset проект продолжит собираться, но соответствующие дополнительные значки в интерфейсе будут пустыми.

Для полноценного публичного форка рекомендуется создать собственные нейтральные изображения с перечисленными именами либо заменить обращения к ним на подходящие SF Symbols. Для личной локальной сборки допускается держать собственные `SystemApp*.imageset` на Mac; добавлять их в Git не следует.

## Настройка проекта под свою команду

В проекте вместо команды разработчика используется заглушка `YOUR_TEAM_ID`. Перед собственной сборкой:

1. Откройте `KleanBytes.xcodeproj`.
2. Для targets `KleanBytes` и `KleanBytesPrivilegedHelper` откройте **Signing & Capabilities**.
3. Выберите свою Team и скопируйте её 10-символьный Team ID из Apple Developer Account или настроек Xcode.
4. Задайте уникальный bundle identifier приложения.
5. Задайте уникальный идентификатор helper.
6. Замените каждое вхождение `YOUR_TEAM_ID` на собственный Team ID:
   - в настройке `DEVELOPMENT_TEAM` обоих targets;
   - `KleanBytes/Services/PrivilegedDeletionService.swift`;
   - `KleanBytesPrivilegedHelper/main.swift`;
   - `Scripts/package-local-app.sh`.
7. Если идентификатор helper изменился, обновите:
   - имя и содержимое plist helper;
   - имя Mach service;
   - обращения к `SMAppService.daemon(plistName:)`;
   - идентификаторы XPC-соединения.

Основное приложение и helper должны быть подписаны одной командой разработчика и взаимно проверять правильные signing identifiers.

Пока `YOUR_TEAM_ID` не заменён во всех перечисленных местах, корректная подпись, соединение с helper и финальная упаковка приложения работать не будут.

## Сборка из Xcode

Для локальной разработки:

1. Выберите scheme `KleanBytesPrivilegedHelper`.
2. Выполните **Product → Build**.
3. Выберите scheme `KleanBytes`.
4. Выполните **Product → Run**.

Обычный продукт Xcode необходимо проверить на наличие встроенного helper. В готовом пакете должны находиться:

```text
KleanBytes.app/
└── Contents/
    ├── Library/
    │   └── LaunchDaemons/
    │       └── com.alllyxer.KleanBytes.PrivilegedHelper.plist
    └── Resources/
        └── KleanBytesPrivilegedHelper
```

## Получение готового приложения

### Автоматическая локальная упаковка

Скрипт `Scripts/package-local-app.sh` автоматизирует полный локальный цикл:

1. собирает `KleanBytesPrivilegedHelper` в конфигурации Release;
2. собирает основное приложение в конфигурации Release;
3. находит локальный сертификат Apple Development;
4. вкладывает helper и его plist в пакет приложения;
5. сначала подписывает helper, затем всё приложение;
6. проверяет итоговую подпись через `codesign --verify`.

Перед запуском замените `YOUR_TEAM_ID` в проекте и самом скрипте на свой 10-символьный Team ID. Затем выполните:

```bash
chmod +x Scripts/package-local-app.sh
./Scripts/package-local-app.sh
```

Если исполняемый атрибут не сохранился, например после загрузки файлов через веб-интерфейс GitHub, скрипт можно запустить напрямую через Zsh:

```bash
zsh Scripts/package-local-app.sh
```

Готовое приложение будет создано здесь:

```text
Build/Local/KleanBytes.app
```

Каталог `Build/` является генерируемым и не должен добавляться в Git.

### Ручная сборка и упаковка

Пример локальной Release-сборки:

```bash
xcodebuild \
  -project KleanBytes.xcodeproj \
  -scheme KleanBytesPrivilegedHelper \
  -configuration Release \
  -derivedDataPath ReleaseDerivedData \
  build

xcodebuild \
  -project KleanBytes.xcodeproj \
  -scheme KleanBytes \
  -configuration Release \
  -derivedDataPath ReleaseDerivedData \
  build
```

Затем helper и plist нужно вложить в пакет приложения:

```bash
APP="ReleaseDerivedData/Build/Products/Release/KleanBytes.app"
HELPER="ReleaseDerivedData/Build/Products/Release/KleanBytesPrivilegedHelper"
PLIST="KleanBytesPrivilegedHelper/com.alllyxer.KleanBytes.PrivilegedHelper.plist"

mkdir -p "$APP/Contents/Library/LaunchDaemons"
cp "$PLIST" "$APP/Contents/Library/LaunchDaemons/"
cp "$HELPER" "$APP/Contents/Resources/KleanBytesPrivilegedHelper"
```

После вложения необходимо сначала подписать helper, затем весь пакет приложения. Замените значения на собственные:

```bash
IDENTITY="Apple Development: YOUR NAME (TEAM)"
HELPER_ID="com.example.KleanBytes.PrivilegedHelper"

codesign --force \
  --identifier "$HELPER_ID" \
  --sign "$IDENTITY" \
  --options runtime \
  "$APP/Contents/Resources/KleanBytesPrivilegedHelper"

codesign --force \
  --sign "$IDENTITY" \
  --options runtime \
  "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
```

Для установки на свой Mac:

1. Полностью закройте предыдущую версию KleanBytes.
2. Перетащите `KleanBytes.app` в `/Applications`.
3. Запустите приложение из Applications.
4. При необходимости разрешите Background Item.
5. Предоставьте Full Disk Access, если нужен расширенный охват сканирования.

Для локальной подписи достаточно Apple ID и доступной в Xcode команды разработки. Для распространения приложения другим пользователям требования строже.

## Публичное распространение

Исходный код можно свободно хранить в GitHub без готовых Releases. Не загружайте:

- сертификаты и закрытые ключи;
- файлы `.p12`;
- пароли нотарификации;
- provisioning profiles;
- DerivedData;
- готовые локально подписанные приложения;
- пользовательские данные Xcode.

Для распространения готового приложения другим людям вне Mac App Store обычно требуются:

- участие в Apple Developer Program;
- сертификат **Developer ID Application**;
- Hardened Runtime для приложения и helper;
- Release Archive;
- нотарификация Apple;
- stapling нотариального билета;
- финальная проверка Gatekeeper.

Удобный официальный путь:

1. **Product → Archive**.
2. Открыть **Window → Organizer**.
3. Выбрать архив.
4. Нажать **Distribute App**.
5. Выбрать **Developer ID**.
6. Отправить приложение на нотарификацию.
7. После успешной проверки экспортировать notarized app.
8. Упаковать приложение в ZIP или DMG и приложить к GitHub Release.

Без Developer ID и нотарификации Gatekeeper на других компьютерах может заблокировать запуск или показать серьёзное предупреждение.

## Рекомендуемый .gitignore

```gitignore
.DS_Store

xcuserdata/
*.xcuserstate
*.xccheckout
*.xcscmblueprint

DerivedData/
ReleaseDerivedData/
Build/
Final-App*/
Distribution*/
*.app
*.dSYM
*.xcarchive

.build/
.swiftpm/
Package.resolved

*.dmg
*.pkg
*.p12
*.cer
*.mobileprovision
*.provisionprofile
*.key
*.pem
.env
.env.*

# Локальные копии иконок приложений Apple
KleanBytes/Assets.xcassets/SystemApp*.imageset/
```

## Что хранить для дальнейшей разработки

Обязательно сохраните:

- исходную папку `KleanBytes`;
- `KleanBytes.xcodeproj`;
- shared schemes;
- исходники helper и его plist;
- Assets и иконку приложения;
- историю Git;
- безопасную резервную копию signing certificate вместе с private key.

Сертификаты и private keys находятся в Keychain, а не внутри проекта. Для резервного восстановления их можно экспортировать в защищённый `.p12`, который нельзя публиковать.

## Лицензия

Перед публикацией открытого репозитория рекомендуется добавить файл `LICENSE`. Без явной лицензии другие люди могут читать код, но юридически не получают стандартного разрешения изменять и распространять его.
