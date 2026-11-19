# Empathy board states — the octopus at work (ADEV-127)

The Astrid icon's octopus acting out each board state, in five metaphors, for choosing which
sets the board views rotate through.

![contact sheet](contact-sheet.png)

| Metaphor | Inbox | Ready | Doing | Waiting | Done |
|---|---|---|---|---|---|
| Race | reading the flyer | on your marks | mid-sprint | water break | podium |
| Building a wall | blueprint | hard hat, trowel | half built | mortar setting | finished |
| Chef | groceries + recipe | apron, mise en place | stirring | oven timer | plated |
| Garden | seed packet | soil dug | watering | sprout coming | bloom |
| Journey | letter arrives | pack + map | on the road | bus stop | summit flag |

- `svg/<metaphor>-<state>.svg`: 512×512 with no text, so any locale can use them.
- `generate.mjs`: the source. One shared octopus (`octo()`: faces `curious`, `grin`,
  `focus`, `calm`, `joy`, with posable arms), plus props per scene. Edit it, then run
  `node docs/design/empathy-states/generate.mjs`. It needs `sharp` from the paired astrid-web
  checkout for the contact sheet.

These are exploration art and are not in the app bundle. Once a set is picked, it goes into
`Assets.xcassets` as its own change.
