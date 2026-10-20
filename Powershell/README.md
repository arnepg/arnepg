# Tøm Teams-cache – Intune Win32-app

## Innhold
- `Install-TeamsCacheCleanup.ps1`: kjører opprydding i brukerens kontekst.
- `Detect-TeamsCacheCleanup.ps1`: midlertidig deteksjon som gjør appen tilgjengelig for ny kjøring etter 15 minutter.
- `README.md`: pakke- og konfigurasjonsveiledning.

## Før produksjon
Test på en liten pilotgruppe. Teams-klienter og cache-stier kan variere etter Teams-versjon. Scriptet sletter kun innhold i disse cacheområdene hvis de finnes:
- `%LOCALAPPDATA%\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams`
- `%APPDATA%\Microsoft\Teams`

Logg: `%LOCALAPPDATA%\Company\Logs\TeamsCacheCleanup.log`

Scriptet må kjøre som **User**, ikke SYSTEM, slik at det kan stoppe og starte Teams i brukerens kontekst. Det er ingen administratorrettigheter som kreves for de oppførte brukerområdene.

## Pakk som .intunewin
1. Last ned Microsoft Win32 Content Prep Tool (`IntuneWinAppUtil.exe`) fra Microsofts offisielle GitHub-repositorium.
2. Legg `IntuneWinAppUtil.exe` i en egen verktøymappe, ikke i kildekatalogen.
3. Åpne PowerShell/CMD og kjør eksempelkommandoen (tilpass stier):
   `IntuneWinAppUtil.exe -c "C:\IntuneSource\TeamsCacheCleanup" -s "Install-TeamsCacheCleanup.ps1" -o "C:\IntuneOutput"`
4. Verktøyet lager `Install-TeamsCacheCleanup.intunewin`.

## Intune-konfigurasjon
Intune Admin Center → Apps → Windows → Add → Windows app (Win32)

**App information**
- Name: `Tøm Teams-cache`
- Description: `Avslutter Teams, rydder lokal Teams-cache og forsøker å starte Teams på nytt. Kjør ved behov.`
- Publisher: organisasjonens navn
- Category: valgfritt, f.eks. Productivity

**Program**
- Install command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-TeamsCacheCleanup.ps1`
- Uninstall command: `cmd.exe /c exit 0`
- Install behavior: `User`
- Device restart behavior: `No specific action`

**Requirements**
- Operating system architecture: 64-bit
- Minimum operating system: velg etter virksomhetens støttede Windows-versjoner

**Detection rules**
- Rules format: `Use a custom detection script`
- Script file: `Detect-TeamsCacheCleanup.ps1`
- Run script as 32-bit process on 64-bit clients: `No`
- Enforce script signature check: `No` (eller signer scriptet og slå på kontroll i tråd med virksomhetens policy)

**Assignments**
- Assign as `Available for enrolled devices` til en pilot-brukergruppe.
- Brukeren åpner Firmaportalen og velger Installer.

## Gjentatt kjøring – viktig begrensning
Deteksjonsscriptet rapporterer appen som installert i 15 minutter etter en kjøring, og som ikke installert etter dette. Det gjør at Firmaportalen/Intune kan tilby Installer igjen etter at deteksjonen er evaluert på nytt. Intune styrer når deteksjon evalueres; derfor er ikke gjenkomst av Installer garantert nøyaktig etter 15 minutter. Test Company Portal-oppførselen i tenant før bred utrulling.

Dette er en handlingsapp, ikke en vanlig installert applikasjon. Hvis organisasjonens Intune-oppsett ikke gir ønsket gjentakelsesflyt, er en egen Company Portal-app/wrapper eller en brukerinitiert Remediation via en støttet portal/workflow et alternativ.

## Logging og feilsøking
Loggfil: `%LOCALAPPDATA%\Company\Logs\TeamsCacheCleanup.log`

Vanlige forhold:
- Hvis Teams ikke er installert eller cache-mappen ikke finnes, logges dette som advarsel.
- Enkelte cachefiler kan være låst. Se etter `WARN` i loggen.
- Oppstart av Teams kan ta mer enn fem sekunder; scriptet logger forsøk, men kan ikke garantere at appen er fullt startet.
