# The focused session screen: VoiceOver by hand

For a device run before `train.focused_session` goes on. VoiceOver can't be judged in the simulator: the tests read the accessibility tree, not what is spoken or when. Turn on the flag (Profile → Developer → Feature flags, or `/v1/config`), then start today's plan with VoiceOver on, in English and once in German. Write each result in `review.md`.

Pass means the app says what's described here, with no silence and no double reading.

## A whole session

- [ ] Log every set of a plan session with VoiceOver only: double tap a row to check it, then follow focus to the next one.
- [ ] After each check, focus stays on the row and it reads "completed".
- [ ] When the page changes, focus lands on the new page's active row and you hear one announcement, such as "Row, set 1 of 4".
- [ ] After the last set you hear "All sets done. Finish workout available at the bottom.", and Finish workout can be reached and activated.
- [ ] A superset flips pages after every set and the announcement names the right exercise each time.
- [ ] A check on an empty row logs nothing, opens the keypad and says "Nothing logged yet. Enter a value on the keypad."
- [ ] The strip reads "Exercise 2 of 5, name, in progress". Swiping up and down changes the page, and focus stays on the strip.

## How "@" and "×" read

The target chip's label holds the same text the chip shows (review N5).

- [ ] The target chip, for example "4 × 8 @ 62.5 kg", reads as something a person would say, in English and German. If "×" reads as "multiplication sign" or "@" as "at sign", write down the exact words. The fix is a spoken label on the chip.
- [ ] The same check on "Next:" in the rest sheet and the rest pill's value, which use "×" too.

## A swipe within 350 ms of a focus move

Focus moves 350 ms after a page change, because a row isn't in the tree before that (review, PR 2).

- [ ] Let a check advance the page, and swipe within about a third of a second. Focus ends where you swiped, or on the active row, but nothing jumps twice.
- [ ] Do the same on the last set: the "All sets done" announcement isn't cut off, and it isn't read after you've moved on. It doesn't go through the pending move's task handle.

## Focus when the pill changes branches

The pill is a different branch of the view when it's idle, running or finished (review, PR 3).

- [ ] With VoiceOver on the running pill, use the "Skip rest" action. Focus stays on the pill, now idle, and it reads "Not running".
- [ ] With VoiceOver on the running pill, let the rest run out. Focus stays on the pill through "Rest over" and back to idle.
- [ ] While a rest runs, the value doesn't read every second. It's read in 5 s steps.
- [ ] Swipe up and down on the running pill: 15 s more or less, and the new time is read.

## The column header

- [ ] The header reads "Table column, Estimated 1RM, button" and its hint.
- [ ] Double tap it: the value is read again as "Estimated 10RM", then "RPE", then "Estimated 1RM".
- [ ] Each row then reads the new estimate, or nothing for a dash, and RPE is read from the row in any mode.
- [ ] At AX3 the header is gone. Rows still read their values, and "Edit RPE" stays in the actions.

## Also

- [ ] Voice Control: "Tap E1RM", "Tap Rest timer", "Tap Finish".
- [ ] Switch Control reaches every row action.
- [ ] Long press on Finish at AX3 shows the large content viewer.
