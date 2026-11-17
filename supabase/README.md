# Supabase för Familjeäventyret

Supabase Free-projektet `Familjeäventyret` ligger i North EU (Stockholm). Projektets URL och endast dess publishable key finns i `../supabase-config.js`.

## Databas

`schema.sql` skapar tabeller, RLS, familjeinbjudningar, veckosysslor, tilldelningar, godkännandeflöde, serverstyrda XP/mynt och diamantkistor.

Om `schema.sql` redan har körts ska även `migrations/20261117_family_limits_and_streak.sql` köras i Supabases SQL Editor. Den begränsar familjen till två aktiva administratörer, ger korrekt streak-framsteg vid godkännande och kontrollerar att varje veckosyssla är tilldelad innan veckan kan stängas.

## Nuvarande appkoppling

- E-postkonto, inloggning och e-postbekräftelse.
- Skapa Familjen Rezaei eller gå med med en engångsinbjudan.
- Admininbjudningar och spelarinbjudningar.
- Aktuell veckoplan skapas för administratörer när den saknas.
- Administratörer skapar sysslor och tilldelar dem till valda familjemedlemmar.
- Spelare skickar in tilldelade sysslor; admins godkänner eller nekar från kön.
- Belöningar delas ut i databasfunktionen efter godkännande. Klienten skriver inte XP eller mynt.
- Appen lyssnar på Supabase Realtime när tabelländringar skickas ut.

Varelseinventarium, kistöppning och köp behöver fortfarande flyttas från prototypens localStorage till säkra databastabeller och RPC-funktioner. De lokala kistorna är därför avstängda för inloggade familjer tills den delen är byggd.

Använd appen via produktionsadressen eller en lokal HTTP-förhandsvisning. Auth-flöden fungerar inte tillförlitligt via `file://`.

Lägg aldrig en `service_role`- eller secret key i klientfilerna.
