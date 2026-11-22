# Supabase för Familjeäventyret

Supabase Free-projektet `Familjeäventyret` ligger i North EU (Stockholm). Projektets URL och endast dess publishable key finns i `../supabase-config.js`.

## Databas

`schema.sql` skapar tabeller, RLS, familjeinbjudningar, veckosysslor, tilldelningar, godkännandeflöde, serverstyrda XP/mynt och diamantkistor.

Om `schema.sql` redan har körts ska migrationsfilerna i `migrations/` köras i datumordning i Supabases SQL Editor. `20261117_family_limits_and_streak.sql` begränsar familjen till två aktiva administratörer, ger streak-framsteg vid godkännande och kontrollerar att varje veckosyssla är tilldelad innan veckan kan stängas. `20261118_chore_difficulty.sql` lägger till svårighetsgraderna Lätt, Mellan och Svår. `20261118_family_management.sql` lägger till säkra familjeåtgärder för att lämna, hantera roller, ta bort medlemmar och radera familjen. `20261118_creature_inventory.sql` skapar RLS-skyddad varelseförvaring och tabeller för aktiva krafteffekter. `20261119_server_chests.sql` flyttar kistköp, slumpning, myntbelöningar för dubbletter och förbannelseuppgifter till en idempotent databasfunktion.

## Nuvarande appkoppling

- E-postkonto, inloggning och e-postbekräftelse.
- Skapa Familjen Rezaei eller gå med med en engångsinbjudan.
- Admininbjudningar och spelarinbjudningar.
- Medlemmar kan lämna familjen; admins kan ändra roller, ta bort medlemmar eller radera familjen. Serverfunktionerna skyddar den sista adminrollen och familjens åtkomst.
- Aktuell veckoplan skapas för administratörer när den saknas.
- Administratörer skapar sysslor och tilldelar dem till valda familjemedlemmar.
- Spelare skickar in tilldelade sysslor; admins godkänner eller nekar från kön.
- Belöningar delas ut i databasfunktionen efter godkännande. Klienten skriver inte XP eller mynt.
- Kistor debiterar mynt, drar varelser och skapar förbannelser i en enda servertransaktion. Dubbletter ger mynt enligt raritet.
- Varelseinventarium och tidsbegränsade krafteffekter har familjeisolerade tabeller; klienten kan läsa sin samling men kan inte själv lägga till eller ändra varelser och effekter.
- Appen lyssnar på Supabase Realtime när tabelländringar skickas ut.

Serverstyrd kistöppning och beständig varelseförvaring är inkopplade. Själva krafteffekterna och aktiveringen av dem byggs i nästa steg.

Använd appen via produktionsadressen eller en lokal HTTP-förhandsvisning. Auth-flöden fungerar inte tillförlitligt via `file://`.

Lägg aldrig en `service_role`- eller secret key i klientfilerna.
