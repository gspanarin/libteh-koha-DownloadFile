# Test plan

Тести потрібно запускати в середовищі встановленого Koha.

Мінімальний набір сценаріїв:

1. 856 без `$l` -> open access.
2. 856 з `$l=open_acces` -> open access.
3. 856 з `$l=authorized_user` -> anonymous denied, logged-in patron allowed.
4. 856 з `$l=staff` -> STAFF allowed, normal patron denied.
5. 856 з `$l=admin` -> admin allowed, normal patron denied.
6. 856 з `$l=local` -> allowed only when remote IP matches configured network.
7. Повторювані `$l`: якщо хоча б одне право дозволяє -> allowed.
8. Повторювані 856: якщо файл прив'язаний до другого 856 -> second field is checked.
9. hashvalue існує, але не присутній у 856$u даного biblionumber -> denied.
10. hashvalue не існує -> denied.
11. Некоректний biblionumber/hashvalue -> denied.
12. Файл знайдено, але file_handle unavailable -> denied.
