import { renderDesktopPreview } from "../src/render";

const preview = document.querySelector(".og-product");
if (preview) preview.innerHTML = renderDesktopPreview("en");
