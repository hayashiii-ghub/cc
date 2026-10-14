# cc: website visuals

The page uses HTML/CSS product illustrations in `app/ShelfPreview.tsx` with
`app/shelf-preview.module.css`. No screenshots or videos are used for the app
previews. The interactive example switches Menu Bar / Notch, filled / empty,
and light / dark appearance using sample items only. It never accesses the
visitor's files or clipboard.

The surrounding typography, neutral dark palette, spacing, and preview controls
follow the Usage Rings site. App illustrations use the macOS system font and
the existing cc: mark. Keep illustrative app controls separate from the real
preview controls so the page does not suggest that it is a working file shelf.

## Social preview

`media/context-og.html` is the editable 1200×630 social-image source. Its shelf is
also rendered as HTML/CSS. Serve `site/` as a local static directory, load
`/media/context-og.html` at 1200×630, wait for local fonts, and save the viewport
to `public/context/context-og.png`. Confirm the saved bytes are PNG; if the browser
returns JPEG, convert the encoding to PNG without resizing. Verify 1200×630 after
conversion.

The headline and description match the site: “A copy for what’s next.” and
“Files, links, and notes. Ready for your next app or agent.” They describe the
app’s saved copies and handoff flow without claiming an origin for the name.

## Favicon

`public/context/context-favicon.svg` uses the existing cc: paths on a dark tile.
It is separate from the transparent mark used on the page. Check it at 16×16
and 32×32 on both light and dark browser backgrounds when changing the mark.

## Historical media

The former public PNG/WebP captures and MP4/WebM files are retained in
`../docs/media-archive/website/`. Its README records their former filenames,
including the three identical Menu Bar WebP files now kept as one copy.
The PNG capture sources remain in `media/`, and the montage source remains in
`../videos/context-hero-montage/`. These historical materials are not referenced
by the current page and do not require rerecording.

Validate with `npm run lint`, `npm test`, and a browser review at desktop and
mobile widths, including all preview controls. Publication requires explicit
authorization.
