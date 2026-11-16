> Copy of `docs/NOCTURNE_STYLE.md` v0.2 from the claude.ai project “RYFT App”, committed verbatim on
> 2026-11-16 as the source of truth for this work. Checked for personal data before commit: none to redact.

# RYFT „Nocturne“ — Premium-Look mit Orbit-Ringen

**Status:** v0.2 · **freigegeben 2026-11-16** · Owner: Tim Krebs
**Mockups (Canvas):** https://claude.ai/artifact/1Gc5U9M2MyFgRKQHwHRtMi — Today, Sleep, Strain, Insights, Profile, Launch-Screen, Icon-Varianten
**Ersetzt:** v0.1 dieses Dokuments (gestrichelter Dial, Ember-Strain) und `docs/ALPINE_STYLE.md` (verworfen 2026-11-14, PR #111).

Nutzerfeedback zu v0.1: Die Elemente der Referenz (Glow-Kacheln, Punktraster, Lineal) wirken professioneller und moderner, aber **die drei Ringe zusammen mit dem Orbit-Logo sind das Markenzeichen** und bleiben. v0.2 verbindet beides.

---

## 1. Entscheidungen (verbindlich)

| Thema | Entscheidung |
|---|---|
| Hero | **OrbitGauge bleibt** — drei Ringe, gleiche Geometrie und Zuordnung wie heute (außen Strain, Mitte geteilt Recovery links / Sleep rechts, innen Readiness). Nur das Rendering wird premium (§3). |
| Farbregel | **Die Ringe sind die Legende.** Jede Metrik hat genau eine Farbe, überall: Ring, Kachel-Glow, Trendlinie, Band. Recovery = Teal, Sleep = Violett, Strain = Blau. Keine weiteren Kachelfarben. |
| Signal | **Volt `#D8FF4F`** nur für: Lineal-Nadel, Readiness-Marker im inneren Ring, „heute“-Punkt in Punktreihen, aktiver Tab-Punkt, Hinweis-Punkt bei Insights. Nie als Text. |
| Glow | Pro Screen-Abschnitt **eine** Glow-Kachel (dunkler Kern, Rand in Metrikfarbe). Alles andere auf neutraler Fläche `#121514`. |
| Hero-Zahl | Pro Screen genau eine Zahl als **Punktraster** (5×7, eigene Shape `DotNumeral`, kein Font): Today = Readiness, Sleep = Schlafdauer, Strain = Strain-Wert. Today hat einen Schalter für dünne Ziffern als Alternative. |
| Typo | Dünne Grotesk, Sentence case, keine Versal-Labels mehr (`OVERALL READINESS` → „Readiness · High“). App: Satoshi bleibt die Familie; Zahlen und Titel Light, Text Regular, Buttons Medium. **Satoshi Light** wird ergänzt. |
| Wordmark | „RYFT“ in Satoshi Light, Laufweite 0.32 em, neben dem Orbit-Logo (Header). |
| App-Icon | **M1 · Light, groß:** Tiefschwarz `#0A0C0B`, „RYFT“ in Satoshi Light, weiß `#F2F1EC`, Laufweite 0.02 em, Schriftgröße ≈ 27 % der Icon-Kante (1024 px → ≈ 280 px). Kein Logo im Icon. Dark/Tinted-Variante identisch. |
| Launch | Ringe zeichnen sich als Anzeige, die drei Punkte fahren in ihre Logo-Position, alles wird weiß = Orbit-Logo, dann „RYFT“ und „Engineered for peak.“ (§5). |
| Modus | Dark-only. |
| Tab-Leiste | Today · Sleep · Strain · Insights · Profile; Punkt statt Icon, aktiver Punkt Volt, Labels 11 pt. Keine schwebende Glas-Leiste mehr. |

## 2. Tokens

| Token | Wert | Verwendung |
|---|---|---|
| `background` | `#0A0C0B` | Screen |
| `surface` | `#121514` | neutrale Kacheln, Listen, Segment-Control |
| `textPrimary` | `#F2F1EC` | Zahlen, Titel |
| `textSecondary` | `#F2F1EC` @ 62 % | Labels, Einheiten |
| `textTertiary` | `#F2F1EC` @ 45 % | Skalen, Meta |
| `separator` | `#F2F1EC` @ 6–8 % | Listen-Trenner, Tab-Leiste |
| `track` | `#F2F1EC` @ 7–16 % | Ring-Spuren, inaktive Ticks |
| `recovery` | `#63D2B4` | Recovery-Ring, -Kachel, -Trend |
| `sleep` | `#9B8AF0` | Sleep-Ring, Hypnogramm, -Trend |
| `strain` | `#5E8BEA` | Strain-Ring, Zonen, HRV-Trend |
| `signal` | `#D8FF4F` | s. §1 |
| `onSignal` | `#0A0C0B` | — |

Die drei Metrikfarben sind die heutigen Ring-Farben, leicht entsättigt; vor PR 1 gegen `Assets.xcassets` abgleichen und nur anpassen, wo Kontrast oder Konsistenz es verlangt (ADR).

**Glow-Kachel:** Grundfarbe = Metrikfarbe, darüber ein radialer Verlauf von `background @ 97 %` (Mitte) → `@ 92 %` (34 %) → `@ 55 %` (68 %) → `@ 10 %` (Rand). Radius 24–28 pt, kein Schatten, kein Rand. Text sitzt immer im dunklen Kern.

**Typo-Skala:** Titel 26 Light · Kachelwert 26–34 Light · Body 15–17 · Label 13 (`textSecondary`) · Caption/Skala 11–12 · Tab 11. Tabellarische Ziffern überall.

**Form:** Screen-Padding 20 · Abstand 12 · Kacheln 22/24/28 · Kreis-Buttons 40 mit 1-pt-Rand @ 16 % · Pill-Buttons 52 hoch, primär hell mit dunklem Icon-Kreis, sekundär Outline.

## 3. OrbitGauge v3 (Rendering, Modell unverändert)

Bei 260 pt Kantenlänge:
- **Außen (Strain):** Spur als Strichring (Ticks 1.2 pt, Abstand ~4.6 pt, `track` 16 %), Bogen 3.5 pt rund.
- **Mitte (Recovery | Sleep):** volle Spur 7 %, zwei Bögen 3.5 pt, getrennt an der Vertikalen wie heute.
- **Innen (Readiness):** Strichring (60 Ticks, 7 pt lang); gefüllt bis zum Wert in `textPrimary`, Rest `track`; **Volt-Punkt** am Wert.
- **Endpunkte:** Punkt r 7 in Metrikfarbe, 3-pt-Rand in `background`, Halo r 15 @ 16 %.
- **Zentrum:** `DotNumeral` (Punkte 5 pt, Abstand 2 pt) oder Light-Ziffern 52 pt.
- Darunter: „Readiness · High“ + Delta in Recovery-Farbe, dann **Lineal** 0–100 mit Band-Zone „high“ (dichtere, hellere Ticks) und Volt-Nadel.
- Die Entrance-Animation (`OrbitGaugeEntrance`) bleibt, sie wird zum Schluss der Launch-Sequenz (§5).

## 4. Screens (wie im Canvas)

| Screen | Aufbau |
|---|---|
| **Today** | Header: Orbit-Logo + Wordmark, Kalender-Button · „Good evening, Tim“ + Datum/Status · OrbitGauge v3 · Label + Delta · Lineal · Glow-Kacheln Recovery (Wert + HRV-Welle) und Sleep (Wert + 7-Nächte-Punktreihe) · Glow-Kachel Strain voll breit (Wert + Lineal 0–21, Ziel 10–14). „My Day“ folgt darunter beim Scrollen, auf `surface`. |
| **Sleep** | Vor/zurück-Kreisbuttons, „Last night · Datum“ · Punktraster-Dauer · „Asleep · 94 % of your need“ · Lineal 0–10 h mit Need-Zone in Sleep-Farbe · Glow-Kachel Hypnogramm (Stufenlinie, Deep-Abschnitte als Sleep-Balken, Phasensummen) · 2×2 neutrale Kacheln: Consistency (Punktreihe), Sleep debt, Efficiency, Restorative. |
| **Strain** | Titel + Plus-Button · Punktraster-Wert · „of 21 · Moderate · in today’s target“ · Lineal mit Zielzone · Glow-Kachel Heart-rate zones (5 Zeilen à 30 Ticks, Minuten rechts) · Steps, Active energy · Activities als Zeilen (Kreis-Icon, Titel, Meta, Strain rechts). |
| **Insights** | Titel + Segment 7 D / 30 D / 90 D · Glow-Kachel „An idea“ (Recovery-Farbe, Volt-Punkt) · Trendkarten Readiness, HRV, Sleep per night: Wert, Delta in Metrikfarbe, Linie über dem 30-Tage-Band. |
| **Profile** | Avatar mit Strain-Ring und Punkt, Name, Sync-Status · Gruppen About you, Devices and sync, Settings · Pill „Export data“ + Outline „Log out“. |

## 5. Launch-Sequenz (5.2 s, Loop nur im Mock; in der App einmal)

Geometrie exakt aus `RyftMarkGeometry` (100er-Box, Ringe r 44 / 25.6 / 7.6, Strich 3.16, Punkt r 6, halfGap außen 14.02°, Mitte 24.22°). Winkel: 0° = 3 Uhr, im Uhrzeigersinn.

| Zeit | Was passiert |
|---|---|
| 0–26 % | Spuren blenden ein. Bögen zeichnen sich als Anzeige in Metrikfarben: Strain von −90° auf 59 %, Sleep von −84° im Uhrzeigersinn, Recovery von −96° gegen den Uhrzeigersinn, Readiness innen auf 84 %. Die drei Punkte reiten auf den Bogenenden. |
| 26–50 % | Halten (Anzeige lesbar). |
| 50–76 % | **Alle drei Punkte fahren in ihre Logo-Position:** Strain-Punkt 122.6° → 65° (+302°, Uhrzeigersinn), Sleep-Punkt 66° → −76° (−142°), Recovery-Punkt −227° → 180° (+407°, volle Runde). Bögen wachsen/schrumpfen auf die Logo-Bögen (außen 79.02°→410.98°, Sleep −51.78°→155.78°, Recovery 204.22°→259.78°), innerer Ring schließt sich. Spuren blenden aus. |
| 76–86 % | Alle Farben → `textPrimary`: das Orbit-Logo steht. |
| 74–86 % | „RYFT“ (Light, 0.9 em → 0.32 em Laufweite) blendet ein. |
| 80–88 % | „Engineered for peak.“ blendet ein. |
| danach | Übergang in Today: das Logo wandert in den Header, OrbitGauge-Entrance startet. |

Reduce Motion: statisches Logo + Wordmark, Cross-Fade in die App. Die Sequenz läuft nur beim Kaltstart, nicht beim Zurückkehren aus dem Hintergrund.

## 6. Barrierefreiheit

Text nur im dunklen Kern der Glow-Kacheln (Snapshot-Test auf Luminanz). Zustand nie nur über Farbe: Nadelposition + Band-Wort + VoiceOver-Satz pro Gauge/Lineal. Dynamic Type bis AX3 (Punktraster fällt ab AX1 auf Light-Ziffern zurück). Reduce Transparency: Glow flach in `surface` mit 2-pt-Rand in Metrikfarbe.

## 7. Umsetzung — PRs in `ryft-app`

| PR | Titel | Inhalt |
|---|---|---|
| 1 | `design: nocturne tokens, type and icon` | Colorsets §2, `signal`, dark-only, Satoshi Light, Typo-Skala ohne Versal-Labels, Wordmark Light, **App-Icon M1** (`scripts/render-icon.swift` auf Wordmark umstellen), ADR 0016 |
| 2 | `design: dot numeral, ruler, glow tile` | `DotNumeral`, `RulerScale` (Band-Zone, Volt-Nadel), `GlowTile`, `DotRow`, `TickRow` (Zonen), Pill-/Kreis-Buttons; Catalog-Einträge und Tests (Ziffernmatrix, Kontrast) |
| 3 | `design: orbit gauge v3 and launch` | Rendering §3 ohne Modelländerung; Launch-Sequenz §5 aus `RyftMarkGeometry`; Gauge-/Mark-Tests neu gepinnt |
| 4 | `today and sleep in nocturne` | Screens §4 |
| 5 | `strain, insights, profile in nocturne` | Screens §4, neue Tab-Leiste |

Danach Website (`ryft-platform/web`): Token-Pipeline zieht die Farben mit; Landing-Layout folgt separat.
