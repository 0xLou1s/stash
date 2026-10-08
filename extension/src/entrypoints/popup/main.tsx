import "@/assets/tailwind.css"

import { StrictMode } from "react"
import { createRoot } from "react-dom/client"
import App from "./App"

// Follow the system appearance.
const darkQuery = window.matchMedia("(prefers-color-scheme: dark)")
const applyTheme = () => document.documentElement.classList.toggle("dark", darkQuery.matches)
applyTheme()
darkQuery.addEventListener("change", applyTheme)

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
