# Release graph renderer

The release job builds this Dockerfile from a small generated context under
`build/tmp/release-renderer`. It uses a pinned Node image and npm lockfile, with
`@resvg/resvg-js` 2.6.2. It converts generated SVG pages to PNG without system
font discovery, so local act and hosted jobs use the same renderer and font.

JetBrains Mono Regular is vendored from commit
`cd5227bd1f61dff3bbd6c814ceaf7ffd95e947d9` (v2.304):
https://github.com/JetBrains/JetBrainsMono/tree/cd5227bd1f61dff3bbd6c814ceaf7ffd95e947d9

Font SHA256: `a0bf60ef0f83c5ed4d7a75d45838548b1f6873372dfac88f71804491898d138f`.
The adjacent OFL.txt contains its license. This tool image is built locally and
is not added to the project build-target catalogue or published to a registry.
