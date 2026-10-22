# Koha plugin: DownloadFile

Клас плагіна:

```perl
Koha::Plugin::Libteh::DownloadFile
```

## Розташування

Для інстансу Koha `<instance>`:

```text
/var/lib/koha/<instance>/plugins/
└── Koha/
    └── Plugin/
        └── LibTeh/
            ├── DownloadFile.pm
            └── DownloadFile/
                ├── templates/
                │   ├── configure.tt
                │   └── denied.tt
                └── t/
                    └── README.md
```

## URL завантаження

```text
/cgi-bin/koha/plugins/run.pl?class=Koha::Plugin::Libteh::DownloadFile&method=download&biblionumber=394&id=HASHVALUE
```

## Права з MARC 856$l

- `open_acces` — відкритий доступ;
- відсутній або порожній `856$l` — відкритий доступ;
- `authorized_user` — авторизований користувач;
- `staff` — користувач із категорією STAFF;
- `admin` — користувач із категорією admin;
- `local` — IP відповідає налаштованій локальній мережі.

Якщо у відповідному 856 є кілька `$l`, достатньо одного права,
яке дозволяє доступ.

Файл додатково перевіряється на належність до конкретного
бібліографічного запису: hashvalue повинен бути присутнім у `856$u`
відповідного поля.

## Форми та CSRF

Усі форми, які змінюють дані, одразу після `<form ...>` повинні містити:

```tt
[% INCLUDE 'csrf-token.inc' %]
```

Операції зміни стану передаються через `name="op"` із префіксом `cud-`,
наприклад:

```html
<input type="hidden" name="op" value="cud-save" />
```

Це правило застосовується до save/update/delete та інших операцій, що змінюють стан.
