import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { CocoPlayground } from "./CocoPlayground";
import { Sheet } from "./sheet";
import { Strips } from "./strips";

const params = new URLSearchParams(location.search);
const dev = import.meta.env.DEV;

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    {dev && params.has("sheet") ? (
      <Sheet />
    ) : dev && params.has("strip") ? (
      <Strips name={params.get("strip") ?? "treat"} />
    ) : (
      <CocoPlayground height="min(72vh, 560px)" />
    )}
  </StrictMode>,
);
