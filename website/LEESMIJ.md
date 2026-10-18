# Kattenoppas Logboek: handleiding voor de developer

Een app waar mensen inloggen met **naam + wachtwoord**, zonder e-mail. Ze kunnen de app op hun gsm zetten als gewone app, met een eigen icoon.

**Hoe het werkt voor de gebruikers:**
- Iedereen maakt eerst een account met naam en wachtwoord.
- Een **eigenaar** maakt in de app een **huis** aan en kiest zelf de **huiscode**.
- **Oppassen** worden lid van dat huis met die code.
- Elk huis ziet alleen zijn eigen leden en bezoeken. Eén oppas kan lid zijn van meerdere huizen en wisselt dan bovenaan van huis.
- De eigenaar ziet de huiscode, kan ze veranderen en kan oppassen uit het huis verwijderen.

Als developer zet je dit één keer op. Daarna hoef je niets meer te doen voor nieuwe huizen of oppassen.

Je hebt twee gratis diensten nodig:
- **Supabase** voor de accounts en de gegevens
- **GitHub Pages** om de app online te zetten

## 1. Database aanmaken (Supabase)

1. Ga naar https://supabase.com, maak een gratis account en klik op **New project**. Kies een naam en de regio *West EU*.
2. Open links **SQL Editor** en klik op **New query**.
3. Plak de volledige inhoud van `supabase-schema.sql` in de editor en klik op **Run**.
   Had je de vorige versie al uitgevoerd? Lees dan eerst de opmerking bovenaan het bestand.
4. Ga naar **Authentication → Sign In / Providers → Email** en zet **Confirm email** **uit**. Klik op **Save**.
   Dit is nodig omdat de logins geen echte e-mailadressen hebben.
5. Ga naar **Project Settings → API** en kopieer:
   - de **Project URL**
   - de **anon public** key

## 2. De app invullen

Open `index.html` in een teksteditor en vul bovenaan deze twee regels in:

```js
const SUPABASE_URL = "https://jouwproject.supabase.co";
const SUPABASE_ANON_KEY = "eyJhbGciOi...";
```

Die anon key mag publiek op GitHub staan; ze is daarvoor gemaakt. Wat iemand mag zien of doen, regelt de database zelf. Zet de **service_role key** nooit in deze bestanden.

## 3. Online zetten (GitHub Pages)

1. Klik op GitHub rechtsboven op **+ → New repository**. Noem ze bv. `kattenoppas`, zet ze op **Public** en klik op **Create repository**.
2. Upload **alles wat in de map `website` zit**: `index.html`, `sw.js`, `manifest.webmanifest`, `.nojekyll` en de map `icons`. Upload de inhoud, niet de map zelf. Dit document en `supabase-schema.sql` mogen erbij, maar dat hoeft niet.
3. Ga naar **Settings → Pages**. Kies bij *Source* voor **Deploy from a branch** en daaronder **main** en **/ (root)**. Klik op **Save**.
4. Na een minuutje staat bovenaan je link, bv. `https://jouwnaam.github.io/kattenoppas/`.

Met git gaat het vanuit de map `website` zo:

```bash
git init -b main
git add .
git commit -m "Kattenoppas Logboek"
git remote add origin https://github.com/JOUWNAAM/kattenoppas.git
git push -u origin main
```

Na een update doet de geïnstalleerde app er tot een minuut over om de nieuwe versie op te halen. Verander je `sw.js`, verhoog dan het nummer in `kattenoppas-v2`.

## 4. Wat je aan een eigenaar stuurt

> Open **[link]** en tik op **Account maken**. Kies daarna **Het zijn mijn katten**, geef je huis een naam en kies een huiscode. Die code stuur je naar je oppassen. Zij openen dezelfde link, maken een account en kiezen **Ik pas op de katten**.

**Als app op de gsm zetten:**
- **iPhone:** open de link in Safari, tik op **Deel** en kies **Zet op beginscherm**.
- **Android:** open de link in Chrome, tik op **⋮** en kies **App installeren**.

## Goed om te weten

- **Namen zijn uniek over de hele app**, omdat de naam ook de login is. Bestaat "Lien" al, dan kiest de tweede bv. "Lien V".
- **Inloggen is niet hoofdlettergevoelig.** "Lien" en "lien" zijn hetzelfde account.
- **Wachtwoord vergeten?** Zonder e-mail is er geen reset-link. Als developer verwijder je het account in Supabase via **Authentication → Users**. Daarna maakt die persoon een nieuw account met dezelfde naam en wordt opnieuw lid met de huiscode.
- **Huiscodes zijn uniek per huis** en niet hoofdlettergevoelig. Spaties worden genegeerd.
- Krijg je bij het aanmaken van een account een fout over een ongeldig e-mailadres? Verander dan in `index.html` de regel `LOGIN_DOMAIN` naar een ander domein. Er worden nooit mails gestuurd.
- Een gratis Supabase-project dat een week niet gebruikt wordt, wordt gepauzeerd. Je zet het met één klik terug aan in het dashboard.
