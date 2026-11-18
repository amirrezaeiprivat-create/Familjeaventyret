# Supabase för Familjeäventyret

Supabase Free-projektet `Familjeäventyret` ligger i North EU (Stockholm). Projektets URL och endast dess publishable key finns i `../supabase-config.js`.

## Databas

`schema.sql` skapar tabeller, RLS, familjeinbjudningar, veckosysslor, tilldelningar, godkännandeflöde, serverstyrda XP/mynt och diamantkistor.

Om `schema.sql` redan har körts ska migrationsfilerna i `migrations/` köras i datumordning i Supabases SQL Editor. `20261117_family_limits_and_streak.sql` begränsar familjen till två aktiva administratörer, ger streak-framsteg vid godkännande och kontrollerar att varje veckosyssla är tilldelad innan veckan kan stängas. `20261118_chore_difficulty.sql` lägger till svårighetsgraderna Lätt, Mellan och Svår. `20261118_family_management.sql` lägger till säkra familjeåtgärder för att lämna, hantera roller, ta bort medlemmar och radera familjen.

## Nuvarande appkoppling

- E-postkonto, inloggning och e-postbekräftelse.
- Skapa Familjen Rezaei eller gå med med en engångsinbjudan.
- Admininbjudningar och spelarinbjudningar.
- Medlemmar kan lämna familjen; admins kan ändra roller, ta bort medlemmar eller radera familjen. Serverfunktionerna skyddar den sista adminrollen och familjens åtkomst.
- Aktuell veckoplan skapas för administratörer när den saknas.
- Administratörer skapar sysslor och tilldelar dem till valda familjemedlemmar.
- Spelare skickar in tilldelade sysslor; admins godkänner eller nekar från kön.
- Belöningar delas ut i databasfunktionen efter godkännande. Klienten skriver inte XP eller mynt.
- Appen lyssnar på Supabase Realtime när tabelländringar skickas ut.

Varelseinventarium, kistöppning och köp behöver fortfarande flyttas från prototypens localStorage till säkra databastabeller och RPC-funktioner. De lokala kistorna är därför avstängda för inloggade familjer tills den delen är byggd.

Använd appen via produktionsadressen eller en lokal HTTP-förhandsvisning. Auth-flöden fungerar inte tillförlitligt via `file://`.

Lägg aldrig en `service_role`- eller secret key i klientfilerna.
