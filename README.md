# fretwork

a sequencer for monome norns

inspired by Ornament + Crime's [CopierMaschine app](https://ornament-and-cri.me/user-manual-v1_3/#anchor-copiermaschine) and a host of music

![screenshot](https://synthetiv.github.io/fretwork/screenshot-1.png)

## first, a word of warning

![under construction](https://synthetiv.github.io/fretwork/pika.gif)

this script, its functionality, and especially its UI are very much subject to change; only as I use it do I discover how I want it to behave. I welcome your input, and I will also welcome reminders to update this documentation when it grows out of date.

## overview

four monophonic voices play notes from repeating patterns, with pitch and gate information stored + edited separately. all may play the same pair of pitch and gate patterns, or different pairs. each pattern may be the same length, or different.

each voice progresses through its pattern at its own rate, which may be randomized per step (jitter). the order in which it reads the pattern may be reversed (retrograde) and/or be randomized (scramble). it can flip the pattern data "vertically," pitch-wise (inversion). a voice may be transposed (bias) and transposition may be randomized per step (noise).

## norns display

the Norns screen shows the paths of the four voices. x = time, y = pitch. dotted lines or gaps indicate a rest (closed gate).

hold *K1* to see the currently selected voice's configuration as an "equation" at the bottom of the screen:
```
+p[-t/(4+0.5y)+1.0k]+0.0z+7.0 [5]
```
means that voice is playing its pitch sequence in retrograde at a rate of 4 steps per clock tick, with jitter of 0.5, scramble of 1.0, no noise, transposed up a fifth. `[5]` denotes the length of the pitch sequence.
```
-g[t/(4+0.5y)]+0.2z [8]
```
means the voice is playing its gate sequence at 4 steps/tick with jitter amount 0.5; a voice always advances through its pitch and gate patterns at the same rate. but this gate sequence is 8 steps long, inverted (i.e. a 'rest' step in the source pattern is a note in this voice, and vice versa), and the noise value of 0.2 means somewhere around 1 in 5 rests will be converted to a note (or vice versa, again), at random.

**E1** selects different voices.

**E2** selects voice parameters.

**E3** changes voice parameters. hold *K3* for fine control.

**K2** switches between editing pitch parameters, gate parameters, and both.

hold **K1** and press **K2** or **K3** to increment/decrement the selected parameter. press K1 or K2 while the other is held to zero out the selected parameter.

## grid

fretwork uses a horizontal, 16x8 grid layout organized in pages. most keys along the left and bottom edges perform the same function no matter what page you're on.

left side (x = 1), center: **voice selectors**. keys flash in time with voice gates. press one to select a voice and it will be highlighted on the norns screen and on the grid. hold one voice's key and press one or more other voices' keys to select multiple voices. double-press one key to select all voices.

**shift**, just below voice selectors, acts as a modifier for many other keys. hold shift and press a voice key to mute the voice.

**ctrl**, in the lower left corner, is also a modifier; in general, holding it will make key presses that might otherwise be delayed until the next sequence step happen right away.

let's hop over to the lower right corner for now:

**record enable**, in the lower right, toggles the ability to edit the pitch sequence. there was a time when this was more useful -- this key will either go away or become useful again sometime soon.

**clock enable** (aka pause), to the left, pauses all voices.

the other keys along the bottom edge of the grid select pages.

**rate** (3, 8) selects the rate page. four sliders, one per voice, to set the number of clock ticks (32nd notes) per step for each voice. left = fewer ticks = faster (yes, this is counterintuitive and I'll probably flip the x axis at some point). the brightest cell in a row indicates the current value. hold shift and press a key near that cell to set jitter; the farther from the lit cell, the more jitter.

**pitch offset** (5, 8) : this page lets you view and set each voice's position in its pitch sequence, MLR-style (sorta). positions are relative to the selected voice (or first selected, if you've selected more than one), so moving that voice will move all others. press a key to move a voice; hold shift and press a key to set scramble (the farther from the center line, the more scramble).

**pitch register** (6, 8) : in the leftmost column of this page, immediately to the right of the voice selectors, are keys for toggling retrograde motion for each voice. to their right are keys for toggling inversion. in the center of the page is a matrix for selecting which pitch sequence should be played back by which voice (column = sequence, row = voice). hold shift and press a key in the matrix to copy the currently selected sequence to that sequence. to the right of the matrix is a set of keys for controlling the length of each voice's sequence. the leftmost of the four keys halves the length, the second decrements the length, third increments length, and the fourth (rightmost) key doubles the length.

**pitch keyboard** (7, 8) : press keys on this page to write to the selected voice(s)'(s) sequence(s)(s). keys are arranged earthsea-/guitar-style, with adjacent semitones in rows and fourths in columns. the two keys in the upper right shift the range by octaves: press (15, 1) to shift down and octave, and (16, 1) to shift up, or hold one and press the other to recenter on octave 0.

**pitch mask keyboard** (8, 8) : pitches in sequences are snapped/quanized to a scale, or you can think of it as a chord; and here you can enable or disable pitch classes in that scale/chord. enabled pitches are shown on the pitch keyboard as "white" keys. you can also toggle pitches from the pitch keyboard page by holding shift and pressing keys.

**transpose keyboard** (9, 8) : press a key to change the transposition of the selected voice. if multiple voices are selected, you can either press keys one at a time, or hold multiple keys in a chord to set the transposition of multiple voices together. hold shift and press a key to set the selected voice's noise (random transposition) amount; the farther from the lit key (indicating current transposition), the more noise.

**gate offset** and **gate register** (11-12, 8) : these work just like the pitch offset and pitch register pages, but for gate sequences.

**gate roll** (13, 8) : view & edit each voice's gate sequence(s). press a key to toggle the gate at that step. each row moves at its voice's rate, and the "play head" is indicated by a brighter column in the center of the grid. the keys in the upper right are navigation: press (15, 1) to toggle follow mode, where notes scroll by and the play head remains in the center, or static mode, where the play head moves and notes stay still. press (14, 1) to activate static mode and move left, and (16, 1) to activate static mode and move right.

finally --

hold **esc** (1, 1) to activate the memory selector. states can be stored and recalled for many of the pages described above. memory slots are displayed in columns corresponding to the key used to select the page (e.g. states for the pitch register page, which include retrograde/inversion status and pattern contents for each voice, are in column 6). press a key to recall a state for a page; hold shift and press a state key to save the current state of that page.

## params

most of this script's params do things that have already been described above, but the "output mode" param is important: it lets you send notes to Crow instead of the internal PolySub engine, either as two voices of pitch + gate, or four voices of pitch only. in 4-voice mode, note data is also sent to MIDI, so you can use a MIDI-CV interface for gates while using crow's precision and slew shapes for pitch.

## one more thing

fretwork is built for microtonality. upload [a Scala file or two](http://www.huygens-fokker.org/scala/downloads.html#scales) to norns and select one using the **tuning file** parameter. 

when using a non-12-tone scale, each row of the grid will be 5 scale degrees apart, _not_ necessarily a perfect fourth. sorry (?) / enjoy (?).

## ok, happy fretting!

thank you for reading all this nonsense. I welcome thoughts, suggestions, bug reports, etc. on lines + github.

![Chinese fretwork wall hanging](https://synthetiv.github.io/fretwork/chinese-fretwork.jpg)
