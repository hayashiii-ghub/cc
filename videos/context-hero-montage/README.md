# Archived hero montage

This directory preserves the editable HyperFrames composition for the previous
10.8-second silent website hero. The current Japanese/English cc: website uses
HTML/CSS app illustrations in `../../site/app/ShelfPreview.tsx` and does not load
this montage or its delivery assets.

The tracked `assets/segments/` clips are the approved public demo takes required to render the composition. High-resolution raw recordings stay local under `assets/source/` and are intentionally ignored. Generated renders, media indexes, thumbnails, snapshots, and audit output are ignored as well.

The footage records the previous product name, mark, and floating shelf. It is
historical material and is intentionally kept without recapture or rendering.

To prepare a new recording, start with [`../../docs/capture-kit/README.md`](../../docs/capture-kit/README.md). When editing or rendering this archived composition:

```sh
npm run check
npm run render
```

Previous optimized website exports are preserved separately in
[`../../docs/media-archive/website/`](../../docs/media-archive/website/README.md).
Its README maps former delivery filenames, including the consolidated still
images. Those exports are historical outputs, not inputs for this composition.

The project pins HyperFrames 0.8.15. The composition loads GSAP 3.14.2 from jsDelivr during validation and rendering, so those commands require network access.
