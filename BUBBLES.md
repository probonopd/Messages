# Speech-bubble transcript

Messages can show a conversation as speech bubbles instead of a plain text
log (Preferences > General > "Show chat as speech bubbles"). This note
describes how that view is built; the code is in `Messages/Bubbles/`.

## Layout

- Incoming messages hug the left margin with the speaker's picture beside
  them; the user's own messages hug the right margin. The geometry alone
  tells who wrote what, so names are not repeated on every line.
- A bubble is at most a fixed fraction of the transcript width
  (`maxBubbleWidthRatio`); text wraps inside it and the bubble is sized from
  the real text layout, so it follows the wrapping the text system does.
- Consecutive messages of the same speaker are packed closer
  (`sameSpeakerGap`) than a change of speaker (`messageGap`).
- Content is laid out from the top and then pushed down, so a short
  transcript hugs the bottom edge and the newest bubble sits next to the
  compose area.
- Date separators appear between messages of different calendar days.
- Older messages loaded from the server are inserted at the top while the
  viewport stays anchored on what the reader was looking at.

## Shape and drawing

Everything is drawn with the OpenStep-era drawing primitives that GNUstep
implements (`NSBezierPath` arcs, clipping, filled strips), without newer
convenience APIs:

- The balloon is a rounded rectangle with a callout ("tail") growing out of
  the side facing the speaker picture. The two corners on that side are
  squarer so the tail sits on a straight edge.
- The fill is a vertical color ramp painted as thin strips inside the
  clipped balloon, with a soft sheen fading out over the upper half
  (`glossIntensity`, 0 for a matte look) and a subtle drop shadow.
- While a participant is typing, a small cloud-shaped bubble (two scallops
  on top plus the tail) is shown beside their picture.
- Speaker pictures fall back to a placeholder whose hue is derived
  deterministically from the nick, so people stay recognizable.

## Colors and theme

All tunables live in `MSGBubbleTheme` (corner radius, tail size, padding,
picture size, gaps, width ratio, gloss, font, colors), so layout and drawing
code do not depend on a palette:

- outgoing bubbles are warm gold, incoming bubbles cool blue, the typing
  cloud a pale neutral;
- incoming bubbles can carry the speaker's nick color, lifted towards white
  (`MSGBubbleTintFromUserColor`) so dark body text stays readable;
- gradient stops, borders and shadows are derived from one base color
  (`MSGBubbleLighten`, `MSGBubbleDarken`).

## Interaction

- Links are detected in the text; the pointer turns into a finger exactly
  over the glyph runs a click would open, and a click re-measures only the
  bubble it landed in.
- Clicking a speaker picture selects that participant (the same as clicking
  the nick in the member list).
- Text can be selected and copied; copying produces the same plain-text
  format as the classic log.

## Performance

Cells cache their laid-out rectangles; the view re-lays out only when the
geometry may have changed (width changes arrive through the autoresizing
mask), and drawing is culled against the dirty rect using each cell's full
painted extent (tail and shadow included).

The view is a self-contained `NSView` (`MSGBubbleTranscriptView`) without
references to other application objects; `BubbleDemo/` shows it on its own.
