# CSS tokens and themes

Use tokens when a value is a shared contract or a documented consumer choice.
Foundation tokens describe scales such as spacing and radius. Semantic tokens
describe roles such as surface, text, border, and focus. Components consume
semantic roles; they do not know a theme's raw palette names.

A theme pack defines the complete set of required semantic roles. Swapping the
pack changes those values while component structure remains stable. A pack
should fail validation if a required role is missing. Themes should be
independent of locale and content; a language may select a different font
without becoming a color theme.

Named elevation is a component choice, including an explicit `none` value.
Do not infer shadow behavior from whether a variable happens to be defined.
Focus, selection, and status need distinguishable treatment beyond shadow.

Keep raw values in their owning scale or theme file. Do not copy a hex color or
shadow string into several component files. Conversely, do not create a global
token for every local pixel; promote a value when its shared meaning is real.

