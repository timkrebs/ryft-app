# TestFlight — What to test

Newest first. Paste the entry into App Store Connect → TestFlight → the build → What to
Test (English and German).

## Next build — beta feedback 2 and the readiness orbit (en + de)

Set the build number when it's uploaded. Character counts (the text between the `text` fences): en 2,199, de 2,489.

**en**

```text
Thanks for the second round of feedback. This build answers it.

TRY FIRST
- Replace an exercise mid-workout, and Undo.
- Finish the last set of an exercise and watch the screen jump to the next one.
- The orbit on Today and on the widget, in light and dark.
- VoiceOver on the orbit, if you use it.

WHAT'S NEW
1. Replace an exercise during a workout: tap the ellipsis button on an exercise (or long-press it) and choose Replace exercise…. Sets you've already done stay with the old exercise, and the new one continues with the rest. Undo is there for 5 seconds. Also change the plan is off by default and applies from your next session.
2. Edit an exercise's sets, reps, weight, rest and notes for this workout. Swipe a set row to delete it.
3. Jump to next exercise: after the last set, the exercise folds into one line and the next set scrolls up. Profile → Training → Jump to next exercise, on by default.
4. The rest timer is a compact bar under the clock, with the next set below it.
5. Last time: an exercise that appears twice in one workout shows its own last sets for each place.
6. Today's baseline counter counts whichever signal is filling. If your tracker doesn't share HRV with Apple Health, the counter counts what does arrive, such as resting heart rate, instead of staying at 0 of 7.
7. The readiness orbit: readiness in the centre, Recovery and Sleep on the inner ring, Strain on the outer. The home and Lock Screen widget draws the same orbit. On a locked iPhone it stays hidden until you unlock.
8. While RYFT learns your baselines, the outer ring fills night by night ("3 / 7"). While last night is being scored, the orbit shows the previous day, dimmed ("Last scored: Yesterday").
9. The orbit assembles when you open the app. With Reduce Motion or Low Power Mode it only fades in.

WHAT'S KNOWN
- The outer ring is strain out of 21. A full ring means all-out, not "good".
- Today's recommended range isn't shown yet.

FEEDBACK
Profile → About → Report a problem. Diagnostics are included if you leave them on (never health values), and reports wait while you're offline. TestFlight's own feedback also works: take a screenshot, tap Share Beta Feedback. Tim reads every one.
```

**de**

```text
Danke für dein zweites Feedback. Dieser Build antwortet darauf.

PROBIER ZUERST
- Eine Übung während des Trainings ersetzen, und „Rückgängig“.
- Den letzten Satz einer Übung abschließen und sehen, wie die Ansicht zur nächsten springt.
- Der Orbit auf Heute und im Widget, hell und dunkel.
- VoiceOver auf dem Orbit, falls du es nutzt.

WAS NEU IST
1. Übung während des Trainings ersetzen: Tippe bei einer Übung auf das Menü (…) oder halte sie gedrückt, und wähle „Übung ersetzen …“. Schon erledigte Sätze bleiben bei der alten Übung, die neue setzt mit den übrigen fort. „Rückgängig“ bleibt 5 Sekunden lang. „Auch im Plan ändern“ ist standardmäßig aus und gilt ab deiner nächsten Einheit.
2. Sätze, Wiederholungen, Gewicht, Pause und Notizen einer Übung kannst du für dieses Training ändern. Wische über eine Satzzeile, um sie zu löschen.
3. Zur nächsten Übung springen: Nach dem letzten Satz klappt die Übung auf eine Zeile zusammen, und der nächste Satz rückt nach oben. Profil → Training → „Zur nächsten Übung springen“, standardmäßig an.
4. Die Pausenzeit ist eine kompakte Leiste unter der Uhr, darunter steht der nächste Satz.
5. Letztes Mal: Kommt eine Übung zweimal in einem Training vor, zeigt jede Stelle ihre eigenen letzten Sätze.
6. Der Zähler für die Ausgangswerte zählt, was gerade ankommt. Sendet dein Tracker HRV nicht an Apple Health, zählt er zum Beispiel den Ruhepuls und bleibt nicht mehr bei 0 von 7 stehen.
7. Der Orbit: Die Bereitschaft steht in der Mitte, Erholung und Schlaf liegen auf dem inneren Ring, die Belastung auf dem äußeren. Das Widget auf dem Home- und dem Sperrbildschirm zeigt denselben Orbit. Auf einem gesperrten iPhone bleibt er verborgen, bis du entsperrst.
8. Solange RYFT deine Ausgangswerte lernt, füllt sich der äußere Ring Nacht für Nacht („3 / 7“). Wird die letzte Nacht noch bewertet, zeigt der Orbit den Vortag abgeblendet („Zuletzt bewertet: Gestern“).
9. Beim Öffnen der App setzt sich der Orbit zusammen. Bei „Bewegung reduzieren“ oder im Stromsparmodus blendet er nur ein.

WAS BEKANNT IST
- Der äußere Ring ist die Belastung von 21. Ein voller Ring heißt: alles gegeben, nicht „gut“.
- Der empfohlene Bereich für heute wird noch nicht angezeigt.

FEEDBACK
Profil → Über RYFT → Problem melden. Diagnosedaten gehen mit, wenn du sie eingeschaltet lässt (nie Gesundheitswerte), und ohne Verbindung wartet die Meldung. Das Feedback von TestFlight geht auch: Bildschirmfoto machen, „Beta-Feedback teilen“ tippen. Tim liest jede Nachricht.
```

## External build for friends — 1.0.0 (en + de)

For the External group (public link + invite code). My Day needs the `today.myday` flag on. Each text stays under App
Store Connect's 4,000 characters (en 1,480, de 1,727, the text between the `text` fences).

**en**

```text
Welcome to the RYFT beta, and thank you for testing!

RYFT turns what your watch or ring writes to Apple Health into three daily numbers: recovery, strain and sleep, each measured against your own baseline. You must be at least 16 to use RYFT.

WHAT TO TEST
1. Sign up and enter the invite code you got from me.
2. Read the consent screen and agree. Nothing is synced before you do.
3. About you: choose your birth year (or skip). It gives an estimate of your maximum heart rate.
4. If RYFT asks what you wear, pick your watch or ring. Then connect Apple Health and allow everything RYFT asks for.
5. The first import: RYFT loads your history from Apple Health. You can leave the app while it runs.
6. Today shows "calibrating" at first. Wear your watch or ring to bed: after the first night you get real scores.
7. My Day on Today: your sleep, workouts and activities for the day. Add an activity and check it appears.

WHAT'S KNOWN
- Calibration takes a few days. Scores sharpen over the first week as RYFT learns your baseline.
- Garmin doesn't share HRV with Apple Health, so readiness waits for it; recovery uses resting heart rate and sleep.
- If last night hasn't reached Apple Health yet, Today says so. Open your tracker's app so it syncs, then pull to refresh.

FEEDBACK
Profile → About → Report a problem. Diagnostics are included if you leave them on (never health values), and reports wait while you're offline. Screenshots with TestFlight's feedback are welcome too.
```

**de**

```text
Willkommen in der RYFT-Beta, und danke, dass du testest!

RYFT macht aus dem, was deine Uhr oder dein Ring in Apple Health schreibt, drei Werte pro Tag: Erholung, Belastung und Schlaf, jeweils gemessen an deinem eigenen Ausgangswert. Du musst mindestens 16 Jahre alt sein, um RYFT zu nutzen.

WAS DU TESTEN KANNST
1. Registriere dich und gib den Einladungscode ein, den du von mir bekommen hast.
2. Lies die Einwilligung und stimme zu. Vorher wird nichts synchronisiert.
3. Über dich: Wähle dein Geburtsjahr (oder überspringe es). Daraus wird deine maximale Herzfrequenz geschätzt.
4. Fragt RYFT, was du trägst, wähle deine Uhr oder deinen Ring. Verbinde dann Apple Health und erlaube alles, worum RYFT bittet.
5. Der erste Import: RYFT lädt deinen Verlauf aus Apple Health. Du kannst die App dabei verlassen.
6. Heute zeigt zuerst „kalibriert noch“. Trag deine Uhr oder deinen Ring nachts: Nach der ersten Nacht bekommst du echte Werte.
7. Mein Tag auf Heute: Schlaf, Workouts und Aktivitäten des Tages. Füge eine Aktivität hinzu und prüfe, ob sie erscheint.

WAS BEKANNT IST
- Die Kalibrierung dauert ein paar Tage. In der ersten Woche werden die Werte genauer, während RYFT deinen Ausgangswert lernt.
- Garmin teilt HRV nicht mit Apple Health, darum wartet die Bereitschaft darauf; die Erholung nutzt Ruhepuls und Schlaf.
- Ist die letzte Nacht noch nicht in Apple Health angekommen, sagt Heute das. Öffne die App deines Trackers, damit sie synchronisiert, und zieh dann zum Aktualisieren.

FEEDBACK
Profil → Über RYFT → Problem melden. Diagnosedaten gehen mit, wenn du sie eingeschaltet lässt (nie Gesundheitswerte), und ohne Verbindung wartet die Meldung. Screenshots über das Feedback von TestFlight sind auch willkommen.
```

## Next build — training import from a CSV file (en + de)

**When the training import is switched on (`train.import`):**
- en: Import a plan and your workout history from the CSV files of Alpha Progression: My Plans → New plan → Import from file,
  or Profile → Data → Import training data. Choose the plans file, the workouts file or both. RYFT shows what it will import
  before anything is sent; only what you confirm is sent. The file is read on your iPhone and is never uploaded.

  Try: export the CSV files from Alpha Progression, save them to Files, choose them here, and check the preview. You can close
  the app during an upload; it continues while RYFT is open. Each item that RYFT leaves out says why, and Details shows the
  request ID.

  Don't expect: every set to come across (sets without weight or reps are skipped and counted), workouts already in RYFT to
  change (they stay as they are, and so does a change you made in RYFT), or importing to be available on every account yet.
  If it isn't available for yours, the import stays on your iPhone and RYFT checks again when you open the app. An import
  that hasn't been sent is kept on your iPhone for up to 30 days; signing out or deleting your account removes it.

- de: Importiere einen Plan und deine Workout-Historie aus den CSV-Dateien von Alpha Progression: Meine Pläne → Neuer Plan →
  Aus Datei importieren, oder Profil → Daten → Trainingsdaten importieren. Wähle die Plan-Datei, die Workout-Datei oder beide.
  Bevor etwas gesendet wird, zeigt RYFT, was importiert wird; gesendet wird nur, was du bestätigst. Die Datei wird auf deinem
  iPhone gelesen und nie hochgeladen.

  Probier aus: Exportiere die CSV-Dateien aus Alpha Progression, speichere sie unter Dateien, wähle sie hier aus und prüfe die
  Vorschau. Du kannst die App während eines Imports schließen; er läuft weiter, solange RYFT geöffnet ist. Jeder Eintrag, den
  RYFT auslässt, sagt dir warum, und unter Details steht die Anfrage-ID.

  Erwarte nicht: dass jeder Satz übernommen wird (Sätze ohne Gewicht oder Wiederholungen werden übersprungen und gezählt), dass
  sich schon in RYFT vorhandene Workouts ändern (sie bleiben, wie sie sind, und das gilt auch für eine Änderung, die du in RYFT
  gemacht hast), oder dass der Import für jedes Konto schon verfügbar ist. Ist er für dein Konto nicht verfügbar, bleibt der
  Import auf deinem iPhone, und RYFT prüft es beim nächsten Öffnen der App erneut. Ein Import, der noch nicht gesendet wurde,
  bleibt bis zu 30 Tage auf deinem iPhone; beim Abmelden oder Löschen deines Kontos wird er entfernt.

## Next build — tracker setup (en + de)

**What's new (live in this build):**
- en: Today names your tracker's app ("Garmin Connect", not "Connect"). In the morning, if your night hasn't reached Apple
  Health yet, Today says so and offers Garmin Connect's App Store page, instead of "Scoring your latest data". If scoring takes
  long, the status line says "Taking longer than usual".
- de: Heute nennt die App deines Trackers („Garmin Connect“ statt „Connect“). Ist deine Nacht morgens noch nicht in Apple Health
  angekommen, sagt Heute das und bietet „Garmin Connect im App Store“ an, statt „Scoring your latest data“. Dauert die Bewertung
  lange, steht in der Statuszeile „Dauert länger als üblich“.

**When tracker setup is switched on (`devices.setup`):**
- en: Tell RYFT what you wear. It shows what reaches RYFT from your tracker and how to set up the sync. Profile → Data →
  Devices & sync → Check sync shows whether each signal arrives. With a Garmin: HRV isn't shared with Apple Health, so
  Readiness waits for it; Recovery uses resting heart rate and sleep.
- de: Sag RYFT, was du trägst. RYFT zeigt dir, was von deinem Tracker ankommt und wie du die Synchronisierung einrichtest.
  Profil → Daten → Geräte & Sync → Sync prüfen zeigt, ob jedes Signal ankommt. Mit einer Garmin: HRV wird nicht mit Apple
  Health geteilt, darum wartet die Bereitschaft darauf; die Erholung nutzt Ruhepuls und Schlaf.

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
