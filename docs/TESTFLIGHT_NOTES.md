# TestFlight — What to test

Newest first. Paste the entry into App Store Connect → TestFlight → the build → What to
Test (English and German).

## Next build — beta feedback 1

Set the build number when it's uploaded. Notifications reach testers through the
`push.enabled` flag, not this build. Turn it on first (`STATUS.md` → Needs you).

**en**

What's new, and what to try:

1. **Change your sleep need** in onboarding (About you), on Sleep (tap Sleep need → Change
   baseline) and in Profile → Sleep. "Sleep need" is tonight's, "Baseline sleep need" is
   the part you set.
2. **Start a workout from anywhere:** Today ("Start strength workout"), a long press on the
   app icon, Siri ("Start a strength workout in RYFT"), the Action Button, or the Control
   Center control. A workout that's already running opens again, never a second one.
3. **New: Bedtime & wake.** Profile → Sleep → Bedtime & wake: your wake times and how much
   of your need you aim for. Tonight on Today (from 17:00) and on Sleep → Bedtime tells you
   when to be in bed, moving with the day's strain. Optional: a reminder to wind down and a
   wake-up alarm (a real alarm on iOS 26 and later).
4. **Save strength workouts to Apple Health**, if you want: asked once after a workout,
   or in Profile → Data.
5. **Notifications** say what's going on: still being rolled out, waiting for your OK, or
   off in iOS Settings.
6. **Refresh is resilient.** Pull to refresh—also while a sync is running or in airplane
   mode. A brief outage no longer shows an error. If data is stale, the line says
   "Showing data from 14:05 · Try again" so you know to retry.
7. **Today shows one state.** No "Baselines · 0 of 7 nights" next to your scores. A
   night that isn't scored yet shows the last scored day, dimmed and dated.
8. **New: Report a problem.** Profile → About → Report a problem: send a message with
   optional diagnostics (app version, build, device, iOS, your last 20 requests, sync
   state, gates and flags, but no health data). Or error card → Details → Send to RYFT.
   Reports queue offline and send on reconnect.

**de**

Was neu ist und was du ausprobieren kannst:

1. **Schlafbedarf ändern** beim Einrichten (Über dich), unter Schlaf (Schlafbedarf tippen →
   Grundbedarf ändern) und in Profil → Schlaf. „Schlafbedarf“ ist der für heute Nacht,
   „Schlaf-Grundbedarf“ der Teil, den du einstellst.
2. **Training von überall starten:** auf Heute („Krafttraining starten“), mit langem Druck
   aufs App-Symbol, mit Siri (vorerst nur auf Englisch: „Start a strength workout in RYFT“),
   der Aktionstaste oder dem Steuerelement im Kontrollzentrum. Ein laufendes Training öffnet
   sich wieder, nie ein zweites.
3. **Neu: Schlafenszeit & Aufwachen.** Profil → Schlaf → Schlafenszeit & Aufwachen: deine
   Aufwachzeiten und wie viel deines Bedarfs du anpeilst. „Heute Nacht“ auf Heute (ab 17 Uhr)
   und unter Schlaf → Schlafenszeit sagt dir, wann du ins Bett solltest, passend zur
   Belastung des Tages. Wahlweise mit Erinnerung ans Runterfahren und Wecker (ein echter
   Wecker ab iOS 26).
4. **Krafttrainings in Apple Health sichern**, wenn du willst: einmal nach einem Training
   gefragt, oder in Profil → Daten.
5. **Mitteilungen** sagen, was los ist: noch in der Einführung, warten auf dein OK, oder in
   den iOS-Einstellungen aus.
6. **Aktualisieren ist zuverlässig.** Zum Aktualisieren ziehen – auch während der Sync
   läuft oder du im Flugzeugmodus bist. Ein kurzer Ausfall zeigt keinen Fehler. Wenn
   Daten länger veraltet sind, sagt die Zeile »Zeigt Daten von 14:05 · Erneut versuchen«.
7. **Heute zeigt einen Zustand.** Kein »Ausgangswerte · 0 von 7 Nächten« mehr neben
   deinen Werten. Eine Nacht, die noch nicht bewertet ist, zeigt den zuletzt bewerteten
   Tag, abgeblendet und mit Datum.
8. **Neu: Problem melden.** Profil → Über RYFT → Problem melden: schreib uns eine
   Nachricht, auf Wunsch mit Diagnose (App-Version, Build, Gerät, iOS, deine letzten 20
   Anfragen, Sync-Status, Gates und Flags – keine Gesundheitswerte). Oder Fehlerkarte →
   Details → An RYFT senden. Ohne Verbindung wartet die Meldung und wird gesendet, sobald
   du wieder online bist.

### Replies to the three comments (2026-10-21)

Send through TestFlight's feedback reply or by email. Testers wrote in English.

> **"Can't adjust the number of hours needed in sleep."**
> Thanks, you're right: it was only in Profile, under another name. Sleep need is editable
> now: in onboarding, on the Sleep tab (tap Sleep need → Change baseline) and in Profile →
> Sleep. It's in the next build.
>
> **"No notifications yet, when are they being rolled out?"**
> They're switching on for the beta this week. You don't need a new build: open RYFT twice
> once they're on and allow notifications when asked. The next build also makes that
> screen clearer while they're still on their way.
>
> **"I got this message when refreshing the screen. Seems like the app is out of sync when
> trying to synchronize my data."**
> Thanks for the report. One part of the refresh was failing, so the whole screen showed
> an error instead of what was already there. Today also showed a calibration state next
> to a score. We've fixed both: each part now loads on its own, and Today shows the right state.
> For the next issue, Profile → About → Report a problem sends us everything we need to
> diagnose in one go.

German, if a tester writes in German:

> **Schlafbedarf:** Danke, das stimmt: Es ging nur im Profil, unter anderem Namen. Der
> Schlafbedarf lässt sich jetzt ändern: beim Einrichten, unter Schlaf (Schlafbedarf tippen →
> Grundbedarf ändern) und in Profil → Schlaf. Das kommt mit dem nächsten Build.
>
> **Mitteilungen:** Sie werden diese Woche für die Beta eingeschaltet. Ein neuer Build ist
> dafür nicht nötig: RYFT danach zweimal öffnen und Mitteilungen erlauben, wenn gefragt. Der
> nächste Build zeigt auf dem Bildschirm auch klarer, wo sie gerade stehen.
>
> **"Ich bekam diese Nachricht beim Aktualisieren des Bildschirms. Es scheint, als wäre die
> App nicht synchron, wenn Daten synchronisiert werden."**
> Danke für deine Meldung. Ein Teil der Aktualisierung ist fehlgeschlagen, deshalb hat der
> ganze Bildschirm einen Fehler gezeigt statt der vorhandenen Daten. Und Heute hat einen
> Kalibrierungszustand neben einem Wert gezeigt. Wir haben beides behoben: Jetzt lädt
> jeder Teil für sich, und Heute zeigt den richtigen Zustand. Für das nächste Mal:
> Profil → Über RYFT → Problem melden schickt uns auf einmal alles, was wir zur
> Analyse brauchen.

## 1.0.0 (build 1) — first beta

**en**

Thanks for testing RYFT. Please try, in this order:
1. **Sign up** with your invite code, agree to the health-data consent, and enter your
   birth year.
2. **Connect Apple Health**, then let the first import finish. It brings in up to 90
   days.
3. **Wear your watch or ring tonight.** Tomorrow, check Today: is the sleep plausible,
   and does recovery look right? Scores sharpen over the first 7 nights.
4. **Train:** log one strength workout from Strain → Start.
5. **Journal:** the next morning, answer "How was yesterday?" on Today.
6. **Report a problem** once (Profile → Report a problem, or a two-finger long-press
   anywhere), even if just to say hi.

TestFlight's own feedback also works: take a screenshot, tap Share Beta Feedback. Tim
reads every one.

**de**

Danke, dass du RYFT testest. Bitte probiere in dieser Reihenfolge:
1. **Registrieren** mit deinem Einladungscode, der Einwilligung zu den Gesundheitsdaten
   zustimmen, Geburtsjahr eintragen.
2. **Apple Health verbinden** und den ersten Import abwarten. Er holt bis zu 90 Tage.
3. **Heute Nacht Uhr oder Ring tragen.** Morgen auf „Heute“ prüfen: Ist der Schlaf
   plausibel, und passt die Erholung? Die Werte werden in den ersten 7 Nächten genauer.
4. **Training:** ein Krafttraining über Belastung → Start erfassen.
5. **Journal:** am nächsten Morgen auf „Heute“ die Frage „Wie war gestern?“ beantworten.
6. **Problem melden**, einmal (Profil → Problem melden, oder mit zwei Fingern lange
   drücken), auch wenn es nur ein Hallo ist.

Das Feedback von TestFlight geht auch: Bildschirmfoto machen, „Beta-Feedback teilen“
tippen. Tim liest jede Nachricht.
